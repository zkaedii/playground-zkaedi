# playground-zkaedi

A Python playground project for experimentation and learning.

## Setup

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install in development mode with dev dependencies
pip install -e ".[dev]"
```

## Development

### Run the application

```bash
playground
# or
python -m playground_zkaedi.main
```

### Run tests

```bash
pytest
pytest --cov  # with coverage
```

### Code quality

```bash
# Linting
ruff check .

# Formatting
ruff format .

# Type checking
mypy src
```

## Project Structure

```
playground-zkaedi/
├── src/
│   └── playground_zkaedi/
│       ├── __init__.py
│       ├── main.py
│       └── py.typed
├── tests/
│   ├── __init__.py
│   └── test_main.py
├── pyproject.toml
├── LICENSE
└── README.md
```

## License

MIT License - see [LICENSE](LICENSE) for details.
