from pathlib import Path

from breadbox.config import BreadboxConfig


class BreadboxProject:
    """
    Represents a breadbox project.

    Encapsulates the hardware configuration and derived paths
    for the build directory structure.
    """

    def __init__(self, config_path: Path) -> None:
        self.config = BreadboxConfig(config_path)
        self.project_dir = self.config.project_dir
        self.build_dir = self.project_dir / "build"
        self.generated_dir = self.build_dir / "breadbox"
