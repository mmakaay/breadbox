from pathlib import Path

import typer
from rich.console import Console

from breadbox.config import BreadboxConfig
from breadbox.errors import ConfigError, BuildError
from breadbox.generator import CodeGenerator
from breadbox.builder import Builder

app = typer.Typer()
console = Console(stderr=True)


@app.command()
def check(project_dir: Path = typer.Argument(".", help="Project directory")) -> None:
    """Load and display the hardware configuration."""
    try:
        BreadboxConfig(project_dir)
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None


@app.command()
def generate(project_dir: Path = typer.Argument(".", help="Project directory")) -> None:
    """Generate ca65 assembly from the hardware configuration."""
    try:
        config = BreadboxConfig(project_dir)
        output_dir = project_dir / "generated" / "breadbox"
        generator = CodeGenerator(config, output_dir)
        generator.generate()
        console.print(f"[green]Generated:[/green] {output_dir}")
    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None


@app.command()
def build(project_dir: Path = typer.Argument(".", help="Project directory")) -> None:
    """Generate assembly and build a ROM binary with ca65/ld65."""
    try:
        config = BreadboxConfig(project_dir)
        output_dir = project_dir / "generated" / "breadbox"

        generator = CodeGenerator(config, output_dir)
        generator.generate()
        console.print(f"[green]Generated:[/green] {output_dir}")

        # Collect user source files from the project directory.
        user_sources = sorted(s for s in project_dir.glob("*.s") if not s.is_relative_to(output_dir))

        builder = Builder(output_dir, project_dir)
        rom_path = builder.build(extra_sources=user_sources)
        size = rom_path.stat().st_size
        console.print(f"[green]Built:[/green] {rom_path} ({size:,} bytes)")

    except ConfigError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(code=1) from None
    except BuildError as e:
        console.print(f"[red]Build error:[/red] {e}")
        raise typer.Exit(code=1) from None
