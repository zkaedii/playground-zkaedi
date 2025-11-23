"""Tests for the main module."""

from playground_zkaedi.main import greet


def test_greet_returns_hello_message():
    result = greet("Alice")
    assert result == "Hello, Alice!"


def test_greet_with_empty_string():
    result = greet("")
    assert result == "Hello, !"


def test_greet_with_special_characters():
    result = greet("World! 🌍")
    assert result == "Hello, World! 🌍!"
