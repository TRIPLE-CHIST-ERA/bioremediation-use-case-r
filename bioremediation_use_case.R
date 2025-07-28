# Load SPARQL functions.
source("../VoIDR.git/R/SPARQL.R")
source("utils.R")

# Set endpoints and SPARQL queries.
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

# Step 1: retrieve pollutants from wikidata. Each pollutant is uniquely
# identified by its CAS registry number (Chemical Abstracts Service).
query_wikidata <- load_query_from_file(query_file_wikidata)
pollutants <- sparql_query(endpoint = endpoint_wikidata, query = query_wikidata)



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



# Step 3. Query the RHEA endpoint using the similar compound names returned
# by the query of step 2.
# The chemical compounds are identified by their ChEBI number.
query_rhea <- load_query_from_file(query_file_rhea)
rhea_reactions <- sparql_query(endpoint = endpoint_rhea, query = query_rhea)

# V2: Add a VALUES clause to set the "?chebi" values retrieved at step 2.
chebi_values <- similar_pollutants_v2 |>
  dplyr::pull("similar_compound_chebi") |>
  stringr::str_replace("http://purl.obolibrary.org/obo/CHEBI_", "CHEBI:") |>
  as_values_clause("similar_compound_chebi")

rhea_reactions_v2 <- sparql_query(
  endpoint = endpoint_rhea,
  query = replace_values_clause(
    "similar_compound_chebi",
    chebi_values,
    query_rhea
  ),
  use_post = TRUE
)
identical(rhea_reactions, rhea_reactions_v2)

# V3: Add a subquery that retrieves "similar_compound_chebi" values using a
# SERVICE clause that runs the subquery on a different endpoint.
#
# Note: since the query is large, we need to pass it via a POST request rather
# than a GET (this is done by passing the "use_post = TRUE" argument).
# This is because with a GET request, only a limited size of text/data can be
# passed in the header of the https request, whereas in a POST request the
# data (sparql request) is not passed in the header of the request.
sub_query_idsm <- load_query_from_file("query_idsm_as_subquery.rq")
rhea_reactions_v3 <- sparql_query(
  endpoint = endpoint_rhea,
  query = replace_values_clause(
    var_name = "similar_compound_chebi",
    replacement = as_service_clause(sub_query_idsm, endpoint_idsm),
    query = merge_query_prefixes(query_rhea, sub_query_idsm)
  ),
  use_post = TRUE
)
# Output is identical, but values are not returned in the same order.
identical(
  rhea_reactions |> arrange(similar_compound_chebi, rhea),
  rhea_reactions_v3 |> arrange(similar_compound_chebi, rhea)
)



# Step 4. Retrieve the uniprot ID associated with a Rhea reaction.
#
# Note: in UniProt, a "mnemonic" is a short human-readable identifier
# assigned to a protein entry. It serves as a convenient shorthand for
# referencing a protein and typically follows the format:
# <PROTEIN>_<SPECIES>
# Example: HBB_HUMAN for human hemoglobin. HBB => abbreviation of the
#          protein name: Hemoglobin subunit beta.
query_uniprot <- load_query_from_file(query_file_uniprot)
uniprot_ids <- sparql_query(
  endpoint = endpoint_rhea,
  query = query_uniprot,
  use_post = TRUE
)

# V2: Add a VALUES clause to set the "?rhea" values retrieved at step 3.
rhea_values <- rhea_reactions_v2 |>
  dplyr::pull("rhea") |>
  unique() |>
  sort() |>
  stringr::str_replace("http://rdf.rhea-db.org/", "rh:") |>
  as_values_clause("rhea")
uniprot_ids_v2 <- sparql_query(
  endpoint = endpoint_rhea,
  query = replace_values_clause("rhea", rhea_values, query_uniprot),
  use_post = TRUE
)
identical(uniprot_ids, uniprot_ids_v2)



# Step 5. Using the OMA database, retrieve all organisms (taxon names)
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
