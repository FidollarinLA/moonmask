"""Install the published package in a fresh consumer and run the real quickstart."""
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="moonmask-consumer-") as directory:
        consumer = Path(directory)
        (consumer / "moon.mod").write_text(
            'name = "acceptance/consumer"\n'
            'version = "0.0.0"\n'
            'import { "FidollarinLA/moonmask@0.1.0" }\n',
            encoding="utf-8",
        )
        main_package = consumer / "cmd/main"
        main_package.mkdir(parents=True)
        for name in ("moon.pkg", "main.mbt"):
            shutil.copyfile(root / "cmd/quickstart" / name, main_package / name)
        for args in (
            ["moon", "update"],
            ["moon", "check", "--deny-warn"],
            ["moon", "build", "--deny-warn"],
            ["moon", "run", "cmd/main"],
        ):
            subprocess.run(args, cwd=consumer, check=True)
        print("PASS: published FidollarinLA/moonmask@0.1.0 works in an independent consumer")


if __name__ == "__main__":
    main()
