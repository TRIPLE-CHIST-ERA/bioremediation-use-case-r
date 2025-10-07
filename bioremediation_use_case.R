# CHIST-ERA TRIPLE demonstrator use-case.
#
# Script that runs a series of SPARQL queries to identify organisms with
# potential bioremediation for a set of chemical pollutants.
#
# Each step of the use-case is run in 3 different ways:
# * Version 1: a "hard-coded" SPARQL query.
# * Version 2: a SPARQL query built by passing values from the previous step
#   of the use-case.
# * Version 3: running all steps up to the query as a single federated query
#   that uses subqueries in SERVICE clauses.
#
# Note: large SPARQL queries must be passed to the endpoint via a POST request
# rather than a GET (this is done by passing the "use_post = TRUE" argument).
# This is because with a GET request, only a limited size of text/data can be
# passed in the header of the HTTPS request, whereas in a POST request the
# data (sparql request) is not passed in the header of the request.

# Load SPARQL functions.
library(sparqlr)
source("utils.R")

# Set endpoints and paths to SPARQL queries.
endpoint_wikidata <- "https://query.wikidata.org/sparql"
endpoint_idsm <- "https://idsm.elixir-czech.cz/sparql/endpoint/idsm"
endpoint_uniprot <- "https://sparql.uniprot.org/sparql"
endpoint_oma <- "https://sparql.omabrowser.org/sparql"

query_file_wikidata <- "queries/query_1_wikidata.rq"
query_file_idsm <- "queries/query_2_idsm.rq"
query_file_uniprot <- "queries/query_3_uniprot.rq"
query_file_oma <- "queries/query_4_oma.rq"
subquery_file_wikidata <- "queries/subquery_1_wikidata.rq"
subquery_file_idsm <- "queries/subquery_2_idsm.rq"
subquery_file_uniprot <- "queries/subquery_3_uniprot.rq"


# ------------------------------------------------------------------------------
# Step 1: retrieve pollutants from wikidata. Each pollutant is uniquely
# identified by its CAS registry number (Chemical Abstracts Service).
query_wikidata <- load_query_from_file(query_file_wikidata)
pollutants <- sparql_select(
  endpoint = endpoint_wikidata,
  query = query_wikidata,
  verbose = TRUE
)



# ------------------------------------------------------------------------------
# Step 2. Query IDSM endpoint to find chemical substances that are similar to
# the chemicals identified via wikidata (step 1).
# The search is made using the CAS numbers: unique IDs for chemical substances,
# that are assigned by the Chemical Abstracts Service (CAS).
query_idsm <- load_query_from_file(query_file_idsm)

# Version 1: use the hard-coded SPARQL query for this step of the use-case.
similar_pollutants <- sparql_select(
  endpoint = endpoint_idsm,
  query = query_idsm,
  verbose = TRUE
)

# Version 2: pass values from the previous step to the SPARQL query.
cas_values <- pollutants |>
  dplyr::pull("cas_number") |>
  sort() |>
  unique() |>
  single_quote() |>
  as_values_clause("cas_number")

similar_pollutants_v2 <- sparql_select(
  endpoint = endpoint_idsm,
  query = replace_values_clause("cas_number", cas_values, query_idsm),
  verbose = TRUE
)
# Verify that result is the same as the original query.
identical(similar_pollutants, similar_pollutants_v2)

# Version 3: run all steps up to this point as a single federated query that
# uses subqueries in SERVICE clauses.
subquery_wikidata <- load_query_from_file(subquery_file_wikidata)
similar_pollutants_v3 <- sparql_select(
  endpoint = endpoint_idsm,
  query = replace_values_clause(
    var_name = "cas_number",
    replacement = as_service_clause(subquery_wikidata, endpoint_wikidata),
    query = merge_query_prefixes(query_idsm, subquery_wikidata)
  ),
  verbose = TRUE
)
# Verify that result is the same as the original query.
identical(similar_pollutants, similar_pollutants_v3)
identical(similar_pollutants_v2, similar_pollutants_v3)


# ------------------------------------------------------------------------------
# Step 3. Query the Rhea and UniProt endpoints to retrieve the proteins/enzymes
# that are involved in the degradation of the chemical compounds (or similar
# chemical compounds) identified at step 2.
# This is done in two steps:
#  1. Query the Rhea endpoint (via a SERVICE clause) to retrieve all similar
#     chemical compounds to those found at step 2 of the use-case. The search
#     uses the ChEBI numbers to identify chemical compounds.
#  2. Retrieve the UniProt identifiers of proteins/enzymes that are part of
#     metabolic reactions in which the identified chemicals take part.
query_uniprot <- load_query_from_file(query_file_uniprot)

# Version 1: use the hard-coded SPARQL query for this step of the use-case.
uniprot_ids <- sparql_select(
  endpoint = endpoint_uniprot,
  query = query_uniprot,
  verbose = TRUE
)

# Version 2: pass values from the previous step to the SPARQL query.
chebi_values <- similar_pollutants_v2 |>
  dplyr::pull("similar_compound_chebi") |>
  sort() |>
  unique() |>
  stringr::str_replace("http://purl.obolibrary.org/obo/CHEBI_", "CHEBI:") |>
  as_values_clause("similar_compound_chebi")

uniprot_ids_v2 <- sparql_select(
  endpoint = endpoint_uniprot,
  query = replace_values_clause(
    "similar_compound_chebi", chebi_values, query_uniprot
  ),
  verbose = TRUE
)
# Verify that result is the same as the original query.
identical(uniprot_ids, uniprot_ids_v2)

# Version 3: run all steps up to this point as a single federated query that
# uses subqueries in SERVICE clauses.
sub_query_idsm <- load_query_from_file(subquery_file_idsm)
uniprot_ids_v3 <- sparql_select(
  endpoint = endpoint_uniprot,
  query = replace_values_clause(
    var_name = "similar_compound_chebi",
    replacement = as_service_clause(sub_query_idsm, endpoint_idsm),
    query = merge_query_prefixes(query_uniprot, sub_query_idsm)
  ),
  verbose = TRUE
)
# Verify that result is the same as the original query.
identical(uniprot_ids, uniprot_ids_v3)



# ------------------------------------------------------------------------------
# Step 4. Using the OMA database, retrieve all organisms (taxon names)
# PROBLEM: it seems that the OMA endpoint does not support POST requests. As
#          a result, we can only submit a query with a limited size, which is
#          why all comments are stripped from the query (remove_comments=TRUE)
#          to save characters.
query_oma <- load_query_from_file(query_file_oma, remove_comments = TRUE)

# Version 1: use the hard-coded SPARQL query for this step of the use-case.
oma_taxons <- sparql_select(
  endpoint = endpoint_oma,
  query = query_oma,
  request_method = "GET",
  verbose = TRUE
)

# Version 2: pass values from the previous step to the SPARQL query.
uniprot_values <- uniprot_ids_v2 |>
  dplyr::pull("uniprot") |>
  unique() |>
  sort() |>
  stringr::str_replace("http://purl.uniprot.org/uniprot/", "upk:") |>
  as_values_clause("uniprot")

oma_taxons_v2 <- sparql_select(
  endpoint = endpoint_oma,
  query = replace_values_clause("uniprot", uniprot_values, query_oma),
  verbose = TRUE
)
# Verify that result is the same as the original query.
identical(oma_taxons, oma_taxons_v2)

# Version 3: run all steps up to this point as a single federated query that
# uses subqueries in SERVICE clauses.
#
# WARNING: this does currently NOT work for a couple of reasons:
#  1. The query is too large, and can't be passed via a GET request. POST
#     requests do not seem to work on the Oma endpoint.
#  2. The request itself does not seem to work when pasted in the endpoint's
#     web interface. The reason why is not fully clear, but maybe it's due to
#     the too many levels of nested SERVICE clauses.
sub_query_uniprot <- load_query_from_file(subquery_file_uniprot)
oma_taxons_v3 <- sparql_select(
  endpoint = endpoint_oma,
  query = replace_values_clause(
    var_name = "uniprot",
    replacement = as_service_clause(sub_query_uniprot, endpoint_uniprot),
    query = merge_query_prefixes(query_oma, sub_query_uniprot)
  ),
  verbose = TRUE
)
# Verify that result is the same as the original query.
identical(oma_taxons, oma_taxons_v3)
