# Chist-ERA TRIPLE demonstrator use-case.

# Load SPARQL functions.
source("../VoIDR.git/R/SPARQL.R")
source("utils.R")

# Set endpoints and paths to SPARQL queries.
endpoint_wikidata <- "https://query.wikidata.org/sparql"
endpoint_idsm <- "https://idsm.elixir-czech.cz/sparql/endpoint/idsm"
endpoint_rhea <- "https://sparql.rhea-db.org/sparql"
endpoint_uniprot <- "https://sparql.uniprot.org/sparql"
endpoint_oma <- "https://sparql.omabrowser.org/sparql"

query_file_wikidata <- "query_wikidata.rq"
query_file_idsm <- "query_idsm.rq"
query_file_rhea <- "query_rhea.rq"
query_file_uniprot <- "query_uniprot.rq"
query_file_oma <- "query_oma.rq"


# ------------------------------------------------------------------------------
# Step 1: retrieve pollutants from wikidata. Each pollutant is uniquely
# identified by its CAS registry number (Chemical Abstracts Service).
query_wikidata <- load_query_from_file(query_file_wikidata)
pollutants <- sparql_query(endpoint = endpoint_wikidata, query = query_wikidata)


# ------------------------------------------------------------------------------
# Step 2. Query IDSM endpoint to find chemical substances that are similar to
# the chemicals identified via wikidata (step 1).
# The search is made using the CAS numbers: unique IDs for chemical substances,
# that are assigned by the Chemical Abstracts Service (CAS).
# The input CAS numbers used for this query were returned by the search from
# step 1.
query_idsm <- load_query_from_file(query_file_idsm)
similar_pollutants <- sparql_query(
  endpoint = endpoint_idsm,
  query = query_idsm,
  use_post = TRUE
)

# V2: Add a VALUES clause to set the "?cas" values retrieved at step 1.
cas_values <- pollutants |>
  dplyr::pull("cas_number") |>
  single_quote() |>
  as_values_clause("cas_number")

similar_pollutants_v2 <- sparql_query(
  endpoint = endpoint_idsm,
  query = replace_values_clause("cas_number", cas_values, query_idsm),
  use_post = TRUE
)
identical(similar_pollutants, similar_pollutants_v2)

# V3: Add a subquery that retrieves "?cas_number" values using a SERVICE clause
#     that runs the subquery on a different endpoint.
sub_query_wikidata <- load_query_from_file("query_wikidata_as_subquery.rq")
similar_pollutants_v3 <- sparql_query(
  endpoint = endpoint_idsm,
  query = replace_values_clause(
    var_name = "cas_number",
    replacement = as_service_clause(sub_query_wikidata, endpoint_wikidata),
    query = merge_query_prefixes(query_idsm, sub_query_wikidata)
  ),
  use_post = TRUE
)
identical(similar_pollutants, similar_pollutants_v3)


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
uniprot_ids <- sparql_query(
  endpoint = endpoint_uniprot,
  query = query_uniprot,
  use_post = TRUE
)

# V2: Add a VALUES clause to set the "?chebi" values retrieved at step 2.
chebi_values <- similar_pollutants_v2 |>
  dplyr::pull("similar_compound_chebi") |>
  sort() |>
  unique() |>
  stringr::str_replace("http://purl.obolibrary.org/obo/CHEBI_", "CHEBI:") |>
  as_values_clause("similar_compound_chebi")

uniprot_ids_v2 <- sparql_query(
  endpoint = endpoint_uniprot,
  query = replace_values_clause(
    "similar_compound_chebi",
    chebi_values,
    query_uniprot
  ),
  use_post = TRUE
)
identical(uniprot_ids, uniprot_ids_v2)


# V3: Add a subquery that retrieves "?similar_compound_chebi" values using a
# nested SERVICE clauses that run all previous steps of the use-case pipeline
# up to this point.
#
# Note: since the query is large, we need to pass it via a POST request rather
# than a GET (this is done by passing the "use_post = TRUE" argument).
# This is because with a GET request, only a limited size of text/data can be
# passed in the header of the https request, whereas in a POST request the
# data (sparql request) is not passed in the header of the request.
sub_query_idsm <- load_query_from_file("query_idsm_as_subquery.rq")
uniprot_ids_v3 <- sparql_query(
  endpoint = endpoint_uniprot,
  query = replace_values_clause(
    var_name = "similar_compound_chebi",
    replacement = as_service_clause(sub_query_idsm, endpoint_idsm),
    query = merge_query_prefixes(query_uniprot, sub_query_idsm)
  ),
  use_post = TRUE
)
identical(uniprot_ids, uniprot_ids_v3)


# ------------------------------------------------------------------------------
# Step 4. Using the OMA database, retrieve all organisms (taxon names)
# PROBLEM: it seems that the OMA endpoint does not support POST requests. As
#          a result, we can only submit a query with a limited size, which is
#          why all comments are stripped from the query (remove_comments=TRUE)
#          to save characters.
query_oma <- load_query_from_file(query_file_oma, remove_comments = TRUE)
oma_taxons <- sparql_query(
  endpoint = endpoint_oma,
  query = query_oma,
  use_post = FALSE
)

# V2: Add a VALUES clause to set the "?uniprot" values retrieved at step 4.
uniprot_values <- uniprot_ids_v2 |>
  dplyr::pull("uniprot") |>
  unique() |>
  sort() |>
  stringr::str_replace("http://purl.uniprot.org/uniprot/", "upk:") |>
  as_values_clause("uniprot")
oma_taxons_v2 <- sparql_query(
  endpoint = endpoint_oma,
  query = replace_values_clause("uniprot", uniprot_values, query_oma),
  use_post = FALSE
)
identical(oma_taxons, oma_taxons_v2)

# V3: Add a subquery that retrieves "?uniprot" values using nested SERVICE
# clauses that run all previous steps of the use-case pipeline up to this
# point.
# WARNING: this does currently NOT work for a couple of reasons:
#  1. The query is too large, and can't be passed via a GET request. POST
#     requests do not seem to work on the Oma endpoint.
#  2. The request itself does not seem to work when pasted in the endpoint's
#     web interface. The reason why is not fully clear, but maybe it's due to
#     the too many levels of nested SERVICE clauses.
sub_query_uniprot <- load_query_from_file("query_uniprot_as_subquery.rq")
oma_taxons_v3 <- sparql_query(
  endpoint = endpoint_oma,
  query = replace_values_clause(
    var_name = "uniprot",
    replacement = as_service_clause(sub_query_uniprot, endpoint_uniprot),
    query = merge_query_prefixes(query_oma, sub_query_uniprot)
  ),
  use_post = FALSE
)
identical(oma_taxons, oma_taxons_v3)
