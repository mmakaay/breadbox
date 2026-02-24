from pathlib import Path

import typer
from rich.console import Console

from breadbox.builder import Builder
from breadbox.errors import BuildError, ConfigError
from breadbox.generator import CodeGenerator
from breadbox.project import BreadboxProject

app = typer.Typer(no_args_is_help=True)
console = Console(stderr=True)


@app.command()
def check(config_file: Path = typer.Argument("config.yaml", help="Configuration file")) -> None:
    """
    Load and display the hardware configuration.
    """
    try:
        BreadboxProject(config_file)
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None


@app.command()
def generate(config_file: Path = typer.Argument("config.yaml", help="Configuration file")) -> None:
    """
    Generate ca65 assembly from the hardware configuration.
    """
    try:
        project = BreadboxProject(config_file)
        generator = CodeGenerator(project.config, project.generated_dir)
        generator.generate()
        console.print(f"[green]Generated:[/green] {project.generated_dir}")
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None


@app.command()
def build(
    config_file: Path = typer.Argument("config.yaml", help="Configuration file"),
    verbose: bool = typer.Option(False, "--verbose", "-v", help="Show detailed build steps"),
) -> None:
    """
    Generate assembly and build a ROM binary with ca65/ld65.
    """
    try:
        if verbose:
            console.print("Loading configuration")
        project = BreadboxProject(config_file)

        if verbose:
            console.print("[green]Assemble source files[/green]")
        generator = CodeGenerator(project.config, project.generated_dir)
        generator.generate()

        builder = Builder(project, verbose=verbose)
        rom_path = builder.build()
        size = rom_path.stat().st_size
        console.print(f"[green]Built:[/green] {rom_path} ({size:,} bytes)")

    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None
    except BuildError as e:
        console.print(f"[red]Build error:[/red] {e}")
        raise typer.Exit(code=1) from None
