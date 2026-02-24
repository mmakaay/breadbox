class ConfigError(Exception):
    """
    Raised when configuration parsing fails.

    Carries a user-facing message with enough context
    (device id, component type) to diagnose the problem
    without a traceback.
    """


class BuildError(Exception):
    """
    Raised when the ca65/ld65 build process fails.

    Carries the stderr output from the failing tool
    for diagnostic purposes.
    """
