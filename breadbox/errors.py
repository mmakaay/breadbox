class ConfigError(Exception):
    """Raised when configuration parsing fails.

    Carries a user-facing message with enough context
    (device id, component type) to diagnose the problem
    without a traceback.
    """
