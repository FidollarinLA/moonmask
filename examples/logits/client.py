"""Line-delimited JSON transport to the MoonBit decoder; no model dependency."""
import json
from pathlib import Path
from queue import Empty, Queue
import subprocess
from threading import Thread

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "_build/js/release/build/cmd/logits/logits.js"


class Decoder:
    def __init__(self, engine=ENGINE, timeout=60):
        if not Path(engine).is_file():
            raise FileNotFoundError("Run: moon build --target js --release cmd/logits")
        self.timeout = timeout
        self.process = subprocess.Popen(
            ["node", str(engine)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, encoding="utf-8", bufsize=1,
        )
        self.responses = Queue()

        def read():
            for line in self.process.stdout:
                self.responses.put(line)
            self.responses.put(None)

        self.reader = Thread(target=read, daemon=True)
        self.reader.start()

    def request(self, op, **fields):
        self.process.stdin.write(json.dumps({"op": op, **fields}, allow_nan=False) + "\n")
        self.process.stdin.flush()
        try:
            line = self.responses.get(timeout=self.timeout)
        except Empty as error:
            self.close()
            raise TimeoutError("MoonBit decoder did not respond") from error
        if line is None:
            raise RuntimeError(f"MoonBit decoder exited: {self.process.poll()}")
        response = json.loads(line)
        if "error" in response:
            raise ValueError(response["error"])
        return response

    def close(self):
        if not self.process.stdin.closed:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)
        self.reader.join(timeout=1)
        self.process.stdout.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
