# CHIST-ERA TRIPLE demonstrator use-case in R language

Use-case demonstrating the federation of open data across SPARQL endpoints,
as part of the CHIST-ERA triple project.

This use-case demonstrator is written in R language, and is available as both
a plain R script, and an Rmarkdown script:

* [Plain R script](bioremediation_use_case.R)
* [Rmarkdown script](bioremediation_use_case.Rmd)
* [Rendered HTML version](https://triple-chist-era.github.io/bioremediation-use-case-r/bioremediation_use_case.html)
  of the Rmarkdown script.

The use case consists of series of SPARQL queries that identify organisms with
possible bioremediation potential for a given pollutant. The queries are
targeting the following 5 SPARQL endpoints:

* [Wikidata](https://query.wikidata.org/sparql)
* [IDSM](https://idsm.elixir-czech.cz/sparql/endpoint/idsm)
* [Uniprot](https://sparql.uniprot.org/sparql)
* [Rhea](https://sparql.rhea-db.org/sparql)
* [OMA](https://sparql.omabrowser.org/sparql)

A version [written in Python](https://github.com/TRIPLE-CHIST-ERA/bioremediation)
is also available.

</br>

## Use-case description

The objective of this use-case is to provide a demonstration showing how data
from different SPARQL endpoints can be combined to retrieve complex
information: in this specific case, identifying organisms with possible
bioremediation potential for a given pollutant.

The steps involved in this demonstrator pipeline are the following:

1. **Query the [Wikidata SPARQL endpoint](https://query.wikidata.org/sparql)**
   to retrieve the **CAS registry number** of one or more pollutants (e.g.
   *atrazine*) for which bioremediation is sought.

2. **Identify chemical compounds that are similar** to the pollutant(s) for
   which bioremediation is sought. This is done to widen the search for
   organisms with potential for bioremediation: if an organism can metabolize
   a closely resembling chemical compound, then it is possible that it can also
   metabolize the original pollutant.

   The search is done via the
   [IDSM sparql endpoint](https://idsm.elixir-czech.cz/sparql/endpoint/idsm),
   which is here queried on the basis of the pollutant's CAS numbers retrieved
   at step 1.

   Each retrieved "similar" chemical compound  is identified by its
   **[ChEBI identifier](https://www.ebi.ac.uk/chebi/aboutChebiForward.do)**.

    > **Chemical Entities of Biological Interest (ChEBI)** is a freely
    > available dictionary of molecular entities focused on "small" chemical
    > compounds.
    > The term "molecular entity" refers to any constitutionally or
    > isotopically distinct atom, molecule, ion, ion pair, radical, radical
    > ion, complex, conformer, etc., identifiable as a separately
    > distinguishable entity.
    > The molecular entities in question are either products of nature or
    > synthetic products used to intervene in the processes of living
    > organisms.

3. **Retrieve metabolic chemical reactions** that involve the pollutant for
   which bioremediation is sought, or one of its similar chemical compounds.

   This is done using the [Rhea service](https://www.rhea-db.org), a
   database of chemical and transport reactions of biological interest.

4. **Retrieve proteins/enzymes** that are involved in the metabolic reactions
   returned by the Rhea endpoint (step 3). This is done using the
   [UniProt service](https://www.uniprot.org), the largest available
   protein database.

5. **Identify the biological organisms** with potential for bioremediation.
   This is done by querying the
   [Oma (Orthologous matrix)](https://omabrowser.org/oma/home) service.
