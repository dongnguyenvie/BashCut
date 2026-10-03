#!/usr/bin/env python3
"""MCP process regression tests. No running app, real token, network or user log is used."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MCPProcessTests(unittest.TestCase):
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
