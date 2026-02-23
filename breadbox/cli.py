from pathlib import Path

import typer
from rich.console import Console

from breadbox.config import BreadboxConfig

#from breadbox.generator import generate

app = typer.Typer()
console = Console()

@app.command()
def generate(project_dir: Path = typer.Argument(".", help="Project directory")) -> None:
    config = BreadboxConfig(project_dir)

# def gen(
#     project_dir: Path = typer.Argument(
#         ".", help="Project directory containing hardware.yml"
#     ),
# ):
#     project_dir = project_dir.resolve()
#     config_path = project_dir / "hardware.yml"

#     if not config_path.exists():
#         typer.echo(f"No hardware.yml found in {project_dir}", err=True)
#         raise typer.Exit(1)

#     config = load_config(config_path)
#     output_dir = project_dir / "generated"
#     generated = generate(config, output_dir)

#     for path in generated:
#         typer.echo(f"  {path.relative_to(project_dir)}")
