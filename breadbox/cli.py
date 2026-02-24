from pathlib import Path

import typer
from rich.console import Console

from breadbox.config import BreadboxConfig
from breadbox.errors import ConfigError

app = typer.Typer()
console = Console(stderr=True)


@app.command()
def generate(project_dir: Path = typer.Argument(".", help="Project directory")) -> None:
    try:
        config = BreadboxConfig(project_dir)
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1)
