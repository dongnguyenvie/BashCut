#!/usr/bin/env python3
"""MCP process regression tests. No running app, real token, network or user log is used."""
import json
from contextlib import contextmanager
import os
from pathlib import Path
import selectors
import socket
import subprocess
import tempfile
import time
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
# BASHCUT_MCP_TEST_EXECUTABLE runs the handshake tests against another build (e.g. a release, to see a fix's test fail).
MCP_EXECUTABLE = Path(os.environ.get('BASHCUT_MCP_TEST_EXECUTABLE') or ROOT / '.build/debug/bashcut-mcp')
# The initialize request Codex 0.160 sends, verbatim. Its object-valued `experimental` capability failed the handshake.
CODEX_INITIALIZE = (b'{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18",'
                    b'"capabilities":{"experimental":{"codex/auth-change":{}},"elicitation":{"form":{},"url":{}}},'
                    b'"clientInfo":{"name":"codex-mcp-client","title":"Codex","version":"0.160.0"}}}')


@contextmanager
def rpc_failure_server(path, failure):
    errors = []
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(path))
    listener.listen(1)
    listener.settimeout(5)

    def serve():
        try:
            connection, _ = listener.accept()
            with connection:
                connection.settimeout(5)
                with connection.makefile('rb') as stream:
                    request = json.loads(stream.readline())
                assert request['token'] == 'test-only-token'
                assert request['method'] == 'timeline.undo'
                connection.sendall(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'error': failure}).encode() + b'\n')
        except Exception as error:
            errors.append(error)

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        yield
    finally:
        thread.join(timeout=6)
        listener.close()
        assert not thread.is_alive(), 'RPC fixture did not finish'
        if errors:
            raise errors[0]


@contextmanager
def rpc_capture_server(path, result):
    """Answers one automation request with `result` and records it in the yielded list."""
    requests = []
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(path))
    listener.listen(1)
    listener.settimeout(5)

    def serve():
        connection, _ = listener.accept()
        with connection:
            connection.settimeout(5)
            with connection.makefile('rb') as stream:
                request = json.loads(stream.readline())
            requests.append(request)
            connection.sendall(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}).encode() + b'\n')

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        yield requests
    finally:
        thread.join(timeout=6)
        listener.close()
        assert not thread.is_alive(), 'RPC fixture did not finish'


class MCPSession:
    """A `bashcut-mcp` process with a private socket path, log and fake token; every read has a deadline."""

    def __init__(self, test, directory):
        test.assertTrue(MCP_EXECUTABLE.is_file(), f'Build bashcut-mcp before running this test ({MCP_EXECUTABLE})')
        self.test = test
        self.socket = Path(directory) / 'automation.sock'
        self.process = subprocess.Popen(
            [str(MCP_EXECUTABLE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={'HOME': directory, 'BASHCUT_SESSION_TOKEN': 'test-only-token', 'BASHCUT_SOCKET': str(self.socket),
                 'BASHCUT_DEBUG_LOG': '1', 'BASHCUT_DEBUG_LOG_PATH': str(Path(directory) / 'debug.log')})
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.pending = b''

    def send_raw(self, line):
        self.process.stdin.write(line + b'\n')
        self.process.stdin.flush()

    def send(self, message):
        self.send_raw(json.dumps(message).encode())

    def receive(self):
        deadline = time.monotonic() + 5
        while b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            self.test.assertGreater(remaining, 0, 'MCP response timed out')
            self.test.assertTrue(self.selector.select(remaining), 'MCP response timed out')
            chunk = os.read(self.process.stdout.fileno(), 65536)
            self.test.assertTrue(chunk, 'MCP exited before replying')
            self.pending += chunk
        line, self.pending = self.pending.split(b'\n', 1)
        return json.loads(line)

    def initialize(self, capabilities, request_id=1):
        self.send({'jsonrpc': '2.0', 'id': request_id, 'method': 'initialize', 'params': {
            'protocolVersion': '2025-06-18', 'capabilities': capabilities,
            'clientInfo': {'name': 'bashcut-test', 'version': '1'}}})
        return self.receive()

    def close(self):
        self.selector.close()
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        for stream in [self.process.stdin, self.process.stdout, self.process.stderr]:
            stream.close()


@contextmanager
def mcp_session(test):
    with tempfile.TemporaryDirectory(prefix='bc-mcp-', dir='/tmp') as directory:
        session = MCPSession(test, directory)
        try:
            yield session
        finally:
            session.close()


class MCPHandshakeTests(unittest.TestCase):
    def assertInitialized(self, response, request_id=1):
        self.assertNotIn('error', response)
        self.assertEqual(response['id'], request_id)
        self.assertEqual(response['result']['serverInfo']['name'], 'bashcut-mcp')

    def test_codex_initialize_then_tools_list(self):
        with mcp_session(self) as session:
            session.send_raw(CODEX_INITIALIZE)
            self.assertInitialized(session.receive(), request_id=0)
            session.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            session.send({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'})
            response = session.receive()
            self.assertEqual(response['id'], 1)
            self.assertIn('bashcut_context_get', [tool['name'] for tool in response['result']['tools']])

    def test_client_capability_shapes(self):
        shapes = {
            'empty': {},
            'elicitation only': {'elicitation': {'form': {}, 'url': {}}},
            'string experimental': {'experimental': {'feature': 'on'}},
            'nested experimental': {'experimental': {'a': {'b': [1, 2.5, None, True]}, 'c': 3}, 'roots': {}},
        }
        for name, capabilities in shapes.items():
            with self.subTest(name), mcp_session(self) as session:
                self.assertInitialized(session.initialize(capabilities))

    def test_escaped_experimental_key(self):
        with mcp_session(self) as session:
            session.send_raw(b'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",'
                             b'"capabilities":{"\\u0065xperimental":{"x":{}}},"clientInfo":{"name":"t","version":"1"}}}')
            self.assertInitialized(session.receive())

    def test_malformed_json_does_not_stop_the_server(self):
        with mcp_session(self) as session:
            session.send_raw(b'{not json')
            self.assertEqual(session.receive()['error']['code'], -32700)
            self.assertInitialized(session.initialize({'experimental': {'x': {}}}))

    def test_later_requests_keep_experimental_fields(self):
        arguments = {'baseRev': 1, 'capabilities': {'experimental': {'codex/auth-change': {}}}, 'experimental': {}}
        with mcp_session(self) as session:
            session.send_raw(CODEX_INITIALIZE)
            self.assertInitialized(session.receive(), request_id=0)
            session.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            with rpc_capture_server(session.socket, {'rev': 2}) as requests:
                session.send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {
                    'name': 'bashcut_timeline_undo', 'arguments': arguments}})
                response = session.receive()
            self.assertEqual(response['id'], 2)
            self.assertFalse(response['result'].get('isError', False))
            self.assertEqual(requests[0]['method'], 'timeline.undo')
            self.assertEqual(requests[0]['params'], arguments)


class MCPProcessTests(unittest.TestCase):
    def test_cli_error_codes_and_data(self):
        with tempfile.TemporaryDirectory(prefix='bc-errors-', dir='/tmp') as directory:
            for code, status in [(-32002, 75), (-32003, 69), (-32001, 77), (-32602, 64), (-32603, 70)]:
                with self.subTest(code=code):
                    path = Path(directory) / f'{code}.sock'
                    log = Path(directory) / f'{code}.log'
                    failure = {'code': code, 'message': 'secret-canary-error', 'data': {'expected': 1, 'actual': 2}}
                    with rpc_failure_server(path, failure):
                        result = subprocess.run([str(ROOT / '.build/debug/bashcut'), 'timeline', 'undo', '--base-rev', '1'],
                            env={'BASHCUT_SOCKET': str(path), 'BASHCUT_SESSION_TOKEN': 'test-only-token',
                                 'BASHCUT_DEBUG_LOG': '1', 'BASHCUT_DEBUG_LOG_PATH': str(log)},
                            capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, status)
                    self.assertEqual(result.stdout, b'')
                    self.assertEqual(json.loads(result.stderr), {'error': failure})
                    self.assertNotIn('secret-canary', log.read_text())

    def test_eof_flushes_private_logs_without_echoing_tool_names(self):
        executable = ROOT / '.build/debug/bashcut-mcp'
        self.assertTrue(executable.is_file(), 'Build bashcut-mcp before running this test')
        with tempfile.TemporaryDirectory(prefix='bashcut-mcp-') as directory:
            log = Path(directory) / 'debug.log'
            process = subprocess.Popen(
                [str(executable)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env={'BASHCUT_DEBUG_LOG': '1', 'BASHCUT_DEBUG_LOG_PATH': str(log),
                     'BASHCUT_SESSION_TOKEN': 'test-only-token',
                     'BASHCUT_SOCKET': str(Path(directory) / 'absent.sock')})
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)

            def send(message):
                process.stdin.write(json.dumps(message).encode() + b'\n')
                process.stdin.flush()

            pending = b''

            def receive():
                nonlocal pending
                deadline = time.monotonic() + 5
                while b'\n' not in pending:
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, 'MCP response timed out')
                    self.assertTrue(selector.select(remaining), 'MCP response timed out')
                    chunk = os.read(process.stdout.fileno(), 65536)
                    self.assertTrue(chunk, 'MCP exited before replying')
                    pending += chunk
                line, pending = pending.split(b'\n', 1)
                return json.loads(line)

            try:
                send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
                    'protocolVersion': '2024-11-05', 'capabilities': {},
                    'clientInfo': {'name': 'bashcut-test', 'version': '1'}}})
                self.assertIn('result', receive())
                send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
                failure = {'code': -32002, 'message': 'secret-canary-error', 'data': {'expected': 1, 'actual': 2}}
                with rpc_failure_server(Path(directory) / 'absent.sock', failure):
                    send({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {
                        'name': 'bashcut_timeline_undo', 'arguments': {'baseRev': 1}}})
                    failed = receive()['result']
                    self.assertTrue(failed['isError'])
                    self.assertEqual(failed['structuredContent'], {'error': failure})
                    self.assertEqual(json.loads(failed['content'][0]['text']), {'error': failure})
                send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {
                    'name': 'secret-canary-tool', 'arguments': {'text': 'secret-canary-argument'}}})
                response = receive()
                self.assertEqual(response.get('id'), 2)
                self.assertTrue(response['result']['isError'])
                process.stdin.close()
                self.assertEqual(process.wait(timeout=5), 0)
                text = log.read_text()
                self.assertIn('tool call', text)
                self.assertIn('unknown tool', text)
                self.assertNotIn('secret-canary', text)
                self.assertEqual(os.stat(log).st_mode & 0o777, 0o600)
            finally:
                selector.close()
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
                for stream in [process.stdin, process.stdout, process.stderr]:
                    stream.close()


if __name__ == '__main__':
    unittest.main()
