"""Main entry point for the playground project."""


def greet(name: str) -> str:
    """Return a greeting message for the given name."""
    return f"Hello, {name}!"


def main() -> None:
    """Main function."""
    print(greet("World"))


if __name__ == "__main__":
    main()
