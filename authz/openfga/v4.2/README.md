# Changelog

`MODIFIES_TUPLES` indicates whether existing tuples are modified when migrating from lower versions. If `TRUE`, modifications are done via migration functions passed to the OpenFGA model manager.

`ADDS_TUPLES` indicates whether new tuples are added to the store during the migration.

## `v4.2`

```
MODIFIES_TUPLES: FALSE
ADDS_TUPLES:     TRUE
```

- Add types `lakekeeper_column` and `lakekeeper_row_policy` for fine-grained access control.
- Add column-level permissions with inheritance from table permissions.
- Add row-level policy permissions with filter-based access control.
- Add actions `can_list_columns`, `can_list_row_policies`, `can_create_column_permission`, `can_create_row_policy` to `lakekeeper_table`.
- Extend existing table and namespace types to support column and row policy relations.