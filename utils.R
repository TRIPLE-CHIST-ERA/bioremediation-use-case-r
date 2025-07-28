# Read a SPARQL query from a `.rq` file and return it as a multi-line string.
load_query_from_file <- function(path, remove_comments = FALSE) {
  query <- readLines(path)
  if (remove_comments) {
    query <- query[!grepl("^\\s*#", query)]
  }
  paste(query, collapse = "\n")
}

# Add single quotes around a string.
single_quote <- function(x) {
  paste0("'", x, "'")
}
curly_bracket_wrap <- function(x) {
  paste0("{ ", x, " }")
}
angle_bracket_wrap <- function(x) {
  paste0("<", x, ">")
}

as_service_clause <- function(query, endpoint) {
  paste(
    "SERVICE",
    angle_bracket_wrap(endpoint),
    curly_bracket_wrap(remove_prefixes(query)),
    sep = " "
  )
}

extract_prefixes_OLD <- function(query) {
  stringr::str_subset(
    strsplit(query, "\n", fixed = TRUE)[[1]],
    "^PREFIX "
  )
}

# Returns the PREFIX values of one or more SPARQL query as a sorted list of
# PREFIXes.
extract_prefixes <- function(...) {
  list(...) |>
    unlist() |>
    strsplit("\n", fixed = TRUE) |>
    unlist() |>
    stringr::str_subset("^PREFIX ") |>
    unique() |>
    sort()
}

remove_prefixes <- function(query) {
  paste(
    stringr::str_subset(
      strsplit(query, "\n", fixed = TRUE)[[1]],
      "^PREFIX ",
      negate = TRUE
    ),
    collapse = "\n"
  )
}

merge_query_prefixes_OLD <- function(query, query_to_merge) {
  merged_prefixes <- sort(
    unique(c(extract_prefixes(query), extract_prefixes(query_to_merge)))
  )
  paste(
    paste(merged_prefixes, collapse = "\n"),
    remove_prefixes(query)
  )
}


# Returns a SPARQL query that a copy of the first query passed to the function,
# but additionally contains the PREFIXes of all other queries passed to the
# function (without creating PREFIX duplication).
merge_query_prefixes <- function(...) {
  # Create a list with the PREFIXex of all queries.
  queries <- list(...)
  merged_prefixes <- do.call(extract_prefixes, queries)
  # merged_prefixes <- extract_prefixes(queries)

  # Replace the PREFIXes of the 1st query with the combined PREFIXes of all
  # queries passed to the function.
  paste(
    paste(merged_prefixes, collapse = "\n"),
    remove_prefixes(queries[[1]]),
    sep = "\n"
  )
}
# q1 <- "PREFIX 7\nPREFIX 2\nPREFIX 3\n\nFoobar\nBarbar"
# q2 <- "PREFIX 4\nBar2\nPREFIX 3"
# q3 <- "PREFIX 5"
# extract_prefixes(q1, q2, q3)
# merge_query_prefixes(q1, q2, q3)
# merge_query_prefixes(, , "PREFIX 5")


as_values_clause <- function(values, var_name) {
  paste(
    "VALUES",
    paste0("?", sub("^\\?", "", var_name)),
    values |>
      paste(collapse = " ") |>
      curly_bracket_wrap(),
    sep = " "
  )
}

# Replaces the VALUES clause "VALUES ?var_name { ... }" with the specified
# replacement value.
replace_values_clause <- function(var_name, replacement, query) {
  sub(
    sprintf("VALUES \\?%s \\{.*?\\}", var_name),
    replacement,
    query
  )
}
