% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/cluster_eigen.R
\name{cluster_eigen}
\alias{cluster_eigen}
\title{This function implements a vector partition algorithm with global
initialization that maximizes the modilarity measure and provide membership
for community assignment. The idea is that the uncontrained solution of
community assignment is the eigenvectors of the modualrity matrix.
We project graph distance matrix to the eigenvectos in order to get a
constrained solution and furture tune current assignment with one-iteration
of k-means clustering or set it as an initialization of a full iteration
of k-means clustering.}
\usage{
cluster_eigen(g, kopt = 2, tune = c("fast", "fine"), verbose = FALSE)
}
\arguments{
\item{g}{The input unweigheted and undirected graph.}

\item{kopt}{The specified number of clusters.}

\item{tune}{Methods selected to tune community assignment by one-iteration
of k-means clustering with "fast" tune or full iteration of k-means
clustering with "fine" tune. Defaut is "fine" tune.}

\item{verbose}{output message}
}
\value{
Returns a list with entries:
\describe{
  \item{k:}{ The number of communities detected in current
           community assignment.}
  \item{modularity:}{ The calculated modularity for current
       community assignment showed by "label" in cluster list.}
  \item{cluster:}{ A list of membership, normalized membership and label for
       current and updated community assignment after tunning.}
  \item{k_up:}{ The number of communities detected in updated
       community assignment.}
  \item{modularity_up:}{ The calculated modularity for updated community
        assignment showed by "label_up" in cluster list.}
}
}
\description{
This function implements a vector partition algorithm with global
initialization that maximizes the modilarity measure and provide membership
for community assignment. The idea is that the uncontrained solution of
community assignment is the eigenvectors of the modualrity matrix.
We project graph distance matrix to the eigenvectos in order to get a
constrained solution and furture tune current assignment with one-iteration
of k-means clustering or set it as an initialization of a full iteration
of k-means clustering.
}
\examples{
\donttest{
library(igraph)
g <- make_full_graph(5) \%du\% make_full_graph(5) \%du\% make_full_graph(5)
g <- add_edges(g, c(1,6, 1,11, 6, 11))
res <- cluster_eigen(g)
plot(g, vertex.color = res$cluster[[1]]$label_up)
}
}
