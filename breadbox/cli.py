from pathlib import Path

import typer
from rich.console import Console

from breadbox.builder import Builder
from breadbox.config import BreadboxConfig
from breadbox.errors import BuildError, ConfigError
from breadbox.generator import CodeGenerator

app = typer.Typer(no_args_is_help=True)
console = Console(stderr=True)


@app.command()
def check(config_file: Path = typer.Argument("config.yaml", help="Configuration file")) -> None:
    """
    Load and display the hardware configuration.
    """
    try:
        BreadboxConfig(config_file)
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None


@app.command()
def generate(config_file: Path = typer.Argument("config.yaml", help="Configuration file")) -> None:
    """
    Generate ca65 assembly from the hardware configuration.
    """
    try:
        config = BreadboxConfig(config_file)
        output_dir = config.project_dir / "build" / "breadbox"
        generator = CodeGenerator(config, output_dir)
        generator.generate()
        console.print(f"[green]Generated:[/green] {output_dir}")
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
        config = BreadboxConfig(config_file)
        project_dir = config.project_dir
        build_dir = project_dir / "build"

        output_dir = build_dir / "breadbox"
        if verbose:
            console.print("Generating assembly")
        generator = CodeGenerator(config, output_dir)
        generator.generate()

        # Collect user source files from the project directory.
        user_sources = sorted(project_dir.glob("*.s"))

        if verbose and user_sources:
            names = ", ".join(s.name for s in user_sources)
            console.print(f"Copying project files ({names})")

        builder = Builder(build_dir, verbose=verbose)
        rom_path = builder.build(user_sources=user_sources)
        size = rom_path.stat().st_size
        console.print(f"[green]Built:[/green] {rom_path} ({size:,} bytes)")

    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None
    except BuildError as e:
        console.print(f"[red]Build error:[/red] {e}")
        raise typer.Exit(code=1) from None
