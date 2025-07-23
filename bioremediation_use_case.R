# Load SPARQL functions.
source("../VoIDR.git/R/SPARQL.R")

# Step 1: retrieve pollutants from wikidata. Each pollutant is uniquely
# identified by its CAS registry number (Chemical Abstracts Service).
#
#   ?compound  wdt:P31   (is instance)        wd:Q113145171 (chemical substance)
#              wdt:P232  (ec number)           ?ec_number
#              wdt:P231  (cas registry number) ?cas_number
#              wdt:P2240 (median lethal dose)  ?ld50
#              wdt:P366  (has use)             ?use_type

endpoint_wikidata <- "https://query.wikidata.org/sparql"
query_wikidata <- "
PREFIX p: <http://www.wikidata.org/prop/>
PREFIX pq: <http://www.wikidata.org/prop/qualifier/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX wd: <http://www.wikidata.org/entity/>

SELECT distinct
    ?use_type
    ?use_typeLabel
    ?compound
    ?compoundLabel
    ?ec_number
    ?cas_number
    (AVG(?ld50) AS ?avg_ld50)
WHERE
{
    # Note: 'wdt:P2240' and 'ld50' is the toxicity level (median lethal
    # dose), not many data points have this info (only 9 results in total).
    ?compound  wdt:P31                     wd:Q113145171 ;
               wdt:P232                    ?ec_number    ;
               wdt:P231                    ?cas_number   ;
               wdt:P2240                   ?ld50         ;
               wdt:P366                    ?use_type     ;
               p:P2240                     ?ref          .
    ?use_type  wdt:P279*                   wd:Q131656    .
    ?ref       pq:P636                     wd:Q285166    ;
               (pq:P689|pq:P2352)/wdt:P279 wd:Q184224    .

    # Helps get the label in your language, if not, then default for all
    # languages, then en language
    SERVICE wikibase:label {
        bd:serviceParam wikibase:language '[AUTO_LANGUAGE],mul,en'.
    }
}

GROUP BY
    ?use_type
    ?use_typeLabel
    ?compound
    ?compoundLabel
    ?ec_number 
    ?cas_number

# Rank by toxicity.
ORDER BY ?avg_ld50
"

pollutants <- sparql_query(endpoint = endpoint_wikidata, query = query_wikidata)

# Add single quotes around a string.
single_quote <- function(x) {
  paste0("'", x, "'")
}
curly_bracket_quote <- function(x) {
  paste0("{ ", x, " }")
}

cas_values_clause <- function(t) {
  paste(
    "VALUES",
    "?cas",
    t |>
      dplyr::pull("cas_number") |>
      single_quote() |>
      paste(collapse = " ") |>
      curly_bracket_quote()
  )
}

# 1 17804-35-2
# 2 17804-35-2
# 3 309-00-2
# 4 86-88-4
# 5 1912-24-9   <- in list
# 6 7773-06-0
# 7 61-82-5     <- in list

# query_solid_pod <- "
# PREFIX sio: <http://semanticscience.org/resource/>

# SELECT ?cas WHERE {
#     ?s sio:SIO_000300 ?cas
# }
# "


# Step 2. Query IDSM endpoint to find chemical substances that are similar to
# the chemicals identified via wikidata (step 1).
# The search is made using the CAS numbers: unique IDs for chemical substances,
# that are assigned by the Chemical Abstracts Service (CAS).
# The input CAS numbers used for this query were returned by the search from
# step 1.

endpoint_idsm <- "https://idsm.elixir-czech.cz/sparql/endpoint/idsm"
query_idsm <- "
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX vocab: <http://rdf.ncbi.nlm.nih.gov/pubchem/vocabulary#>
PREFIX sachem: <http://bioinfo.uochb.cas.cz/rdf/v1.0/sachem#>
PREFIX endpoint: <https://idsm.elixir-czech.cz/sparql/endpoint/>

SELECT
    ?cas
    ?compound
    ?similar_compound
    ?score
WHERE
{
    {
        # Pollutant CAS numbers retrieved from wikidata.
        VALUES_CLAUSE

        # * sio:SIO_000011     ->  'is attribute of'
        # * sio:SIO_000300     ->  'has value'
        # * sio:CHEMINF_000446 ->  'CAS registry number'
        ?synonym  sio:SIO_000300  ?cas               ;
                  a               sio:CHEMINF_000446 ;
                  sio:SIO_000011  ?compound          .
        ?compound a               vocab:Compound     .

        # SIO_011120  ->  'molecular structure file'
        ?attribute  a               sio:SIO_011120 ;  
                    sio:SIO_000011  ?compound      ;
                    sio:SIO_000300  ?molfile       .

        SERVICE endpoint:chebi {
            # ?x sachem:similaritySearch  ?y  .
            #
            # ?x sachem:compound          ?similar_compound                 ;
            #   sachem:score             ?score                            .
            # ?y sachem:query             ?molfile                          ;
            #   sachem:cutoff            '0.7'^^xsd:double                 ;
            #   sachem:similarityRadius  '3'^^xsd:integer                  ;
            #   sachem:aromaticityMode   sachem:aromaticityDetectIfMissing ;
            #   sachem:tautomerMode      sachem:inchiTautomers             .

            [
                sachem:compound ?similar_compound ;
                sachem:score    ?score
            ] sachem:similaritySearch [
                sachem:query             ?molfile                          ;
                sachem:cutoff            '0.7'^^xsd:double                 ;
                sachem:similarityRadius  '3'^^xsd:integer                  ;
                sachem:aromaticityMode   sachem:aromaticityDetectIfMissing ;
                sachem:tautomerMode      sachem:inchiTautomers
            ] .
        }
    }

    UNION
    {
        SERVICE endpoint:chebi {
          ?similar_compound sachem:substructureSearch [ sachem:query '[As]' ] .
        }
    }
}
ORDER BY DESC(?score)
"





similar_pollutants <- sparql_query(
  endpoint = endpoint_idsm,
  query = sub("VALUES_CLAUSE", cas_values_clause(pollutants), query_idsm)
)



# Step 3. Query the RHEA endpoint using the similar compound names returned
# by the query of step 2.
# The chemical compounds are identified by their ChEBI number.
#
# Chemical Entities of Biological Interest (ChEBI) is a freely available
# dictionary of molecular entities focused on ‘small’ chemical compounds.
# The term ‘molecular entity’ refers to any constitutionally or isotopically
# distinct atom, molecule, ion, ion pair, radical, radical ion, complex,
# conformer, etc., identifiable as a separately distinguishable entity.
# The molecular entities in question are either products of nature or
# synthetic products used to intervene in the processes of living organisms.

endpoint_rhea <- "https://sparql.rhea-db.org/sparql"
query_rhea <- "
PREFIX CHEBI: <http://purl.obolibrary.org/obo/CHEBI_>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX rh: <http://rdf.rhea-db.org/>

SELECT DISTINCT
    ?chebi
    ?rhea
    ?equation
    ?uniprot
WHERE
{
    # ChEBI values retrieved from IDSM endpoint.
    # Example: <http://purl.obolibrary.org/obo/CHEBI_15930>, which can be
    # abbreviated CHEBI:15930
    VALUES ?chebi { CHEBI:15930 }
    
    # The ChEBI can be used either as a small molecule, the reactive part of
    # a macromolecule, or as a polymer.
    ?compound  ( rh:chebi | 
                (rh:reactivePart/rh:chebi) |
                (rh:underlyingChebi/rh:chebi) )  ?chebi .

    ?rhea  rdfs:subClassOf                  rh:Reaction ;
           rh:equation                      ?equation   ;
           rh:side/rh:contains/rh:compound  ?compound   .
  
    
}
"

rhea_reactions <- sparql_query(endpoint = endpoint_rhea, query = query_rhea)



# Step 4. Retrieve the uniprot ID associated with a Rhea reaction.
#
# Note: in UniProt, a "mnemonic" is a short human-readable identifier
# assigned to a protein entry. It serves as a convenient shorthand for
# referencing a protein and typically follows the format:
# <PROTEIN>_<SPECIES>
# Example: HBB_HUMAN for human hemoglobin. HBB => abbreviation of the
#          protein name: Hemoglobin subunit beta.


# endpoint_uniprot <- "https://sparql.uniprot.org/sparql"
query_uniprot <- "
PREFIX rh: <http://rdf.rhea-db.org/>
PREFIX up: <http://purl.uniprot.org/core/>

SELECT
    ?uniprot
    ?mnemo
    ?rhea
    ?accession
    ?equation
WHERE
{
    SERVICE <https://sparql.uniprot.org/sparql> {
        GRAPH <http://sparql.uniprot.org/uniprot> {
            
            # Values that were retrieved from the Rhea endpoint.
            # Example: <http://rdf.rhea-db.org/11312
            VALUES ?rhea { rh:11312 rh:11313 }

            ?uniprot  up:reviewed  true    ;
                      up:mnemonic  ?mnemo  ;
                      up:organism  ?taxid  ;
                      up:annotation/
                      up:catalyticActivity/
                      up:catalyzedReaction   ?rhea  .
        }
    }

    ?rhea  rh:accession  ?accession  ;
           rh:equation   ?equation   .
}
"

uniprot_ids <- sparql_query(endpoint = endpoint_rhea, query = query_uniprot)



# Step 5. Using the OMA database, retrieve all organisms (taxon names)

endpoint_oma <- "https://sparql.omabrowser.org/sparql"
query_oma <- "
#PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
#PREFIX owl: <http://www.w3.org/2002/07/owl#>
#PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
#PREFIX dc: <http://purl.org/dc/elements/1.1/>
#PREFIX dct: <http://purl.org/dc/terms/>
#PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
#PREFIX ensembl: <http://rdf.ebi.ac.uk/resource/ensembl/>
#PREFIX oma: <http://omabrowser.org/ontology/oma#>
#PREFIX sio: <http://semanticscience.org/resource/>
#PREFIX taxon: <http://purl.uniprot.org/taxonomy/>
#PREFIX void: <http://rdfs.org/ns/void#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX orth: <http://purl.org/net/orth#>
PREFIX up: <http://purl.uniprot.org/core/>
PREFIX lscr: <http://purl.org/lscr#>

SELECT
    ?ortholog_protein
    ?oma_link
    ?taxon_sci_name
WHERE
{
    # Uniprot reference retrieved in the previous step.
    VALUES ( ?uniprot_link ) { ( <http://purl.uniprot.org/uniprot/P72156> ) }
     

    # Retrieve the protein for which we want to search orthologs.
    ?protein  lscr:xrefUniprot  ?uniprot_link  .

    # The three that contains Orthologs. The leafs are proteins.
    # This graph pattern defines the relationship protein1 is orthologs
    # to protein2
    ?cluster  a                          orth:OrthologsCluster ;
              orth:hasHomologousMember   ?node1                ,
                                         ?node2                .
    ?node1    orth:hasHomologousMember*  ?protein              .
    ?node2    orth:hasHomologousMember*  ?ortholog_protein     .

    # OMA link to the second protein.
    ?ortholog_protein  rdfs:seeAlso       ?oma_link       ;
                       orth:organism/
                       obo:RO_0002162/
                       up:scientificName  ?taxon_sci_name .

    FILTER(?node1 != ?node2)
}
"
