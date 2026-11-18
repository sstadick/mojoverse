from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from std.tempfile import TemporaryDirectory
from std.pathlib import Path
from threads import Worker, available_parallelism, spawn


def summarize(var values: List[Int]) raises -> String:
    var total = 0
    for value in values:
        total += value
    return String("sum=", total)


def fail(var message: String) raises -> Int:
    raise Error(message)


def write_file(var path: String) raises:
    with open(path, "w") as file:
        file.write("finished")


def no_input(var value: NoneType) -> Int:
    return 23


def test_owned_threads() raises:
    var first = spawn[summarize]([7, -2, 31])
    var second = spawn[summarize]([100, 3])
    var moved = first^
    assert_equal(second.join(), "sum=103")
    assert_equal(moved.join(), "sum=36")
    with assert_raises():
        _ = moved.join()
    var failed = spawn[fail](String("worker failure"))
    try:
        _ = failed.join()
        assert_true(False)
    except error:
        assert_equal(String(error), "worker failure")
    var directory = TemporaryDirectory()
    var path = String(Path(directory.name) / "result")
    var discarded = spawn[write_file](path.copy())
    _ = discarded^
    with open(path, "r") as file:
        assert_equal(file.read(), "finished")
    var writer = spawn[write_file](path.copy())
    writer.join()
    with assert_raises():
        writer.join()
    var empty_input = spawn[no_input](None)
    assert_equal(empty_input.join(), 23)


struct Job(Movable):
    var worker: Worker
    var request: Int
    var result: Int
    var ready: Bool
    var stop: Bool

    def __init__(out self) raises:
        self.worker = Worker()
        self.request = 0
        self.result = 0
        self.ready = False
        self.stop = False


def compute(address: Int) abi("C") -> Int:
    ref job = Pointer[Job, MutUntrackedOrigin](unsafe_from_address=address)[]
    job.worker.lock()
    while True:
        while not job.ready and not job.stop:
            job.worker.wait()
        if job.stop:
            break
        var input = job.request
        job.worker.unlock()
        # Exercise real Mojo allocation/destruction on the native thread.
        var values = List[Int]()
        for i in range(64):
            values.append(input + i)
        var text = String(input)
        var sum = text.byte_length()
        for value in values:
            sum += value
        job.worker.lock()
        job.result = sum
        job.ready = False
        job.worker.notify_all()
    job.worker.unlock()
    return 0


def test_persistent_workers() raises:
    assert_true(available_parallelism() >= 1)
    var jobs = List[Job](capacity=4)
    for _ in range(4):
        jobs.append(Job())
    # Stable storage for every callback, including across restart after join.
    for _ in range(2):
        for i in range(4):
            jobs[i].stop = False
            var address = Int(jobs.unsafe_ptr().unsafe_offset(i))
            jobs[i].worker.unsafe_start[compute](address)
        var rejected = False
        try:
            var address = Int(jobs.unsafe_ptr())
            jobs[0].worker.unsafe_start[compute](address)
        except:
            rejected = True
        var correct = rejected
        for step in range(100):
            for i in range(4):
                ref job = jobs[i]
                job.worker.lock()
                job.request = 1000 + 17 * step + 3 * i
                job.ready = True
                job.worker.notify_all()
                job.worker.unlock()
            for i in range(4):
                ref job = jobs[i]
                job.worker.lock()
                while job.ready:
                    job.worker.wait()
                # All inputs have four decimal digits; sum 0..63 = 2016.
                correct &= job.result == 64 * (1000 + 17 * step + 3 * i) + 2016 + 4
                job.worker.unlock()
        for i in range(4):
            jobs[i].worker.lock()
            jobs[i].stop = True
            jobs[i].worker.notify_all()
            jobs[i].worker.unlock()
            jobs[i].worker.join()
            jobs[i].worker.join()
        assert_true(correct)
    assert_equal(len(jobs), 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
