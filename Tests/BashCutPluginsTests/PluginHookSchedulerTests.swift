import BashCutPlugins
import Testing

@Suite("Plugin hook scheduling")
struct PluginHookSchedulerTests {
    @Test("A thousand subscribers never run more than the limit, and each hears the event once")
    func limit() {
        var scheduler = PluginHookScheduler<String>(limit: 4)
        for index in 0..<1000 { scheduler.enqueue("p\(index):timeline.changed", plugin: "p\(index)") }
        #expect(scheduler.queued == 1000)
        var started: [String] = []
        var peak = 0
        var generator = SystemRandomNumberGenerator()
        while true {
            while let next = scheduler.next() { started.append(next.plugin) }
            peak = max(peak, scheduler.running.count)
            guard let done = scheduler.running.randomElement(using: &generator) else { break }
            scheduler.finish(done)
        }
        #expect(peak == 4)
        #expect(started.count == 1000 && Set(started).count == 1000)
        #expect(started.prefix(4) == ["p0", "p1", "p2", "p3"])
        #expect(scheduler.queued == 0)
    }

    @Test("One delivery per plugin at a time, and plugins take turns")
    func turns() {
        var scheduler = PluginHookScheduler<String>(limit: 1)
        for event in ["a1", "a2", "a3"] { scheduler.enqueue(event, plugin: "a") }
        scheduler.enqueue("b1", plugin: "b")
        var order: [String] = []
        while let next = scheduler.next() {
            order.append(next.key)
            scheduler.finish(next.plugin)
        }
        #expect(order == ["a1", "b1", "a2", "a3"])

        var wide = PluginHookScheduler<String>(limit: 4)
        wide.enqueue("a1", plugin: "a")
        wide.enqueue("a2", plugin: "a")
        #expect(wide.next()?.key == "a1")
        #expect(wide.next()?.key == nil, "a plugin's second event waits for its first")
        wide.finish("a")
        #expect(wide.next()?.key == "a2")
    }

    @Test("A waiting event of the same kind is queued once, and reset drops the queue")
    func coalesce() {
        var scheduler = PluginHookScheduler<String>(limit: 1)
        scheduler.enqueue("busy", plugin: "x")
        _ = scheduler.next()
        scheduler.enqueue("a:edit", plugin: "a")
        scheduler.enqueue("a:edit", plugin: "a")
        #expect(scheduler.queued == 1)
        scheduler.removeQueued()
        #expect(scheduler.queued == 0)
        scheduler.finish("x")
        #expect(scheduler.next()?.key == nil && scheduler.running.isEmpty)
        scheduler.finish("x")
        #expect(PluginHookScheduler<String>(limit: 0).limit == 1)
    }
}
