# Repository Guidelines

## Project Structure & Module Organization

This repository contains the design and delivery files for a single-parking-lot database project. `docs/` contains requirements, the data model, implementation plan, task checklist, and final review. `diagrams/` contains editable draw.io diagrams, report-ready PNG exports, and the original backups under `diagrams/backups/`. `report/停车场管理项目报告.docx` is the final report, while `report/build/` holds report scripts, screenshots, and render/validation artifacts. The `sql/` directory contains the MySQL schema and sample data, query documentation, field design, and Chinese-to-English name mapping.

## Build, Test, and Development Commands

There is no application build or automated test suite. Use MySQL 8.0.16 or later (8.0.30+ recommended), or MySQL Workbench 8.0 CE. From a POSIX shell, execute the complete script with:

```sh
mysql --default-character-set=utf8mb4 -u <user> -p < sql/停车场管理数据库.sql
```

The script creates `parking_management_db`, drops and recreates its eight business tables, and reloads sample data. Run it only against a disposable or intended project database. Verify query results against `sql/查询说明.md`; commented invalid inserts near the end of the script are optional constraint checks for a disposable database.

## Coding Style & Naming Conventions

Use full English `snake_case` for SQL tables, columns, indexes, and constraints; follow prefixes already used in the schema, such as `idx_`, `uk_`, `fk_`, and `chk_`. Keep SQL keywords uppercase, identifiers backtick-quoted, and DDL indented with four spaces. Preserve Chinese business labels and explanatory prose. When a schema name changes, update the model, SQL, field documentation, query guide, mapping, and report together. No formatter or linter is configured.

## Testing Guidelines

Validate schema changes by executing the full SQL script on MySQL and checking its sample queries and constraints. Keep example results in `sql/查询说明.md` consistent with the seeded data. No separate coverage threshold or test naming convention applies.

## Commit & Pull Request Guidelines

This checkout has no Git history, so existing commit conventions cannot be confirmed. Use short imperative commit subjects (for example, `Update parking fee query`). Pull requests should summarize affected deliverables, state the MySQL version and validation performed, and include screenshots when diagram or report layout changes.
