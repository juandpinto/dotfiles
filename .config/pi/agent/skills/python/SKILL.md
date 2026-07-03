---
name: python
description: Python coding guidelines for data science projects. Use when user is writing, editing, or reviewing Python code, or asks about Python tooling, code style, Spark/Databricks, or data visualization.
---

# Python guidelines

- Unless otherwise specified, write Python code in a "*.py" file but following a notebook-like style with `# %%` cell delimiters. This allows for easier readability and execution in interactive environments. The main exception is if the file is meant to be run within Databricks and begins with the line `# Databricks notebook source`, in which case the cell delimiter should be `# COMMAND ----------`.
- When running Python code, always use `uv`. For example, instead of `python script.py`, run `uv run script.py`. This ensures that the code is executed in the correct virtual environment with all dependencies properly managed.
- Use `ruff` for linting and code formatting. Use `ty` for type checking.
- Docstrings should be in the Google style.
- Don't split long lines in comments or docstrings with manual line breaks, even if they exceed PEP 8's line length limit—let the editor wrap them visually. Never insert `\n` or line continuation characters in prose text, unless explicitly separating paragraphs.
- When using pySpark:
  - Include `spark = SparkSession.getActiveSession()` and `assert spark is not None, "No active SparkSession"` after importing packages near the top of the file.
  - Assume that a serverless Databricks cluster is being used, which means no caching is available. Aside from this, aim for optimized Spark code. This includes avoiding unnecessary actions that execute the same transformations multiple times.
- For data visualizations, always import `seaborn` and rely on it where possible. For more advanced tweaking, use `matplotlib` directly (but still have `seaborn` imported to ensure the styling is consistent).
