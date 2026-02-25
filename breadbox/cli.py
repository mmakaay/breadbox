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
def check(config_path: Path = typer.Argument("config.yaml", help="Configuration file")) -> None:
    """
    Load and display the hardware configuration.
    """
    try:
        project = BreadboxProject(config_path)
        console.print("")
        project.config.print_config(console)
        console.print("\n[green]Configuration OK\n")
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None


@app.command()
def generate(config_path: Path = typer.Argument("config.yaml", help="Configuration file")) -> None:
    """
    Generate ca65 assembly from the hardware configuration.
    """
    try:
        console.print("[green]Generate code[/green]")
        project = BreadboxProject(config_path)
        generator = CodeGenerator(project)
        generator.generate()
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None


@app.command()
def build(
    config_path: Path = typer.Argument("config.yaml", help="Configuration file"),
    verbose: bool = typer.Option(False, "--verbose", "-v", help="Show detailed build steps"),
) -> None:
    """
    Generate assembly and build a ROM binary with ca65/ld65.
    """
    try:
        project = BreadboxProject(config_path)

        console.print("[green]Generate code[/green]")
        generator = CodeGenerator(project)
        generator.generate()

        console.print("[green]Assemble code[/green]")
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
