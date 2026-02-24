from pathlib import Path

import typer

from breadbox.config import BreadboxConfig

app = typer.Typer()


@app.command()
def generate(project_dir: Path = typer.Argument(".", help="Project directory")) -> None:
    config = BreadboxConfig(project_dir)
