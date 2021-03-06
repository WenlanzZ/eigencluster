#' @title This function implements a vector partition algorithm with global
#' initialization that maximizes the modilarity measure and provide membership
#' for community assignment. The idea is that the uncontrained solution of
#' community assignment is the eigenvectors of the modualrity matrix.
#' We project graph distance matrix to the eigenvectos in order to get a
#' constrained solution and furture tune current assignment with one-iteration
#' of k-means clustering or set it as an initialization of a full iteration
#' of k-means clustering.
#'
#' @param g The input unweigheted and undirected graph.
#' @param kopt The specified number of clusters.
#' @param tune Methods selected to tune community assignment by one-iteration
#' of k-means clustering with "fast" tune or full iteration of k-means
#' clustering with "fine" tune. Defaut is "fine" tune.
#' @param verbose output message
#' @return
#' Returns a list with entries:
#' \describe{
#'   \item{k:}{ The number of communities detected in current
#'            community assignment.}
#'   \item{modularity:}{ The calculated modularity for current
 #'        community assignment showed by "label" in cluster list.}
#'   \item{cluster:}{ A list of membership, normalized membership and label for
#'        current and updated community assignment after tunning.}
#'   \item{k_up:}{ The number of communities detected in updated
#'        community assignment.}
#'   \item{modularity_up:}{ The calculated modularity for updated community
#'         assignment showed by "label_up" in cluster list.}
#' }
#' @examples
#' \donttest{
#' library(igraph)
#' g <- make_full_graph(5) %du% make_full_graph(5) %du% make_full_graph(5)
#' g <- add_edges(g, c(1,6, 1,11, 6, 11))
#' res <- cluster_eigen(g)
#' plot(g, vertex.color = res$cluster[[1]]$label_up)
#' }
#' @import tidyverse
#' @import foreach
#' @import igraph
#' @import doParallel
#' @import parallel
#' @importFrom purrr map map_dbl map_int
#' @importFrom tibble as_tibble add_column
#' @importFrom lsa cosine
#' @importFrom dplyr group_by group_map mutate arrange desc select
#' @importFrom bcp bcp
#' @importFrom DMwR SoftMax
#' @importFrom here here
#' @importFrom wordspace normalize.rows
#' @importFrom psych tr
#' @export

cluster_eigen <- function(g,
                          kopt = 2,
                          tune = c("fast", "fine", "kmeans"),
                          verbose = FALSE) {
    n        <- vcount(g)
    if (is_weighted(g)) {
      W <- as_adjacency_matrix(g, attr="weight")
      D <- matrix(0, n, n); diag(D) <- rowSums(W)
      eclidean <- diag(1, n) - as.matrix(W)
      # mod <- (1 / n^2) * matrix(1, n, n) - (1 / n) * solve(D, W)
      mod <- solve(D, W)
    } else {
      eclidean <- diag(1, n) - as.matrix(as_adjacency_matrix(g))
      mod      <- modularity_matrix(g, seq_len(length(V(g))))
    }
    dim_time <- system.time(
        results <- dimension(mod,
                             components = min(n, 50),
                             decomposition =  "eigen",
                             method = "kmeans"))
    lambda   <- results$subspace$sigma_a
    u        <- results$subspace$u
    mod_cal <- function(mem) {
        # S <- matrix(0, n, length(unique(mem)))
        # for(i in 1:n) S[i, mem[i]] <- 1
        # tr(as.matrix(t(S) %*% mod %*% S)) / (2 * gsize(g))
        modularity(g, mem, weights = E(g)$weight)
    }
    registerDoParallel(detectCores())
    mem_cal <- function(gd, kopt = 2) {
        foreach(s = switch(2 - is.null(kopt),
                           seq_len(ncol(gd)),
                           kopt)) %dopar% {
            # max cosine similarity
            mem <- gd[, seq_len(s)] %>% apply(1, max)
            label <-  gd[, seq_len(s)] %>%
                      apply(1, function(x) which(x %in% mem)[1])
            # check unique cluster number
            uc <- seq(s)[!seq(s) %in% unique(label)]
            label[sample(seq_len(length(label)), length(uc))] <- uc
            tibble(mem = mem, mem_norm = SoftMax(mem), label = label)
        }
    }
    # dimension determination
    if (missing(kopt)) {
        kopt <- NULL
        dim  <- min(results$dimension + 1, sum(lambda > 0))
    } else if (max(kopt) <= sum(lambda > 0)) {
        dim  <- max(kopt)
        cat("max dim up to ", sum(lambda > 0), ".\n")
    } else {
        kopt <- seq(min(kopt), sum(lambda > 0))
        dim  <- max(kopt)
        warning("max dim up to ", sum(lambda > 0), ".\n")
    }
    # weighted graph
    if (is_weighted(g)) {
      um <- normalize.rows(u[, seq_len(dim)], method = "euclidean", p = 2)
      cosine_time <- system.time(suppressMessages(
      gd <- as_tibble(
            foreach(i = seq_len(nrow(eclidean)), .combine = rbind) %dopar%
              apply(um, 2, function(x)
                cosine(eclidean[i, ], x)
              ),
            .name_repair = "unique")))
      res <- tibble(k = switch(2 - is.null(kopt),
                               seq_len(ncol(gd)),
                               kopt))
      mem_time  <- system.time(mem <- mem_cal(gd, kopt = kopt))
      res$cluster <- switch(tune,
              fast = {
                  Map(function(x, y) x %>% add_column(y),
                      mem, mem %>% lapply(`[[`, 3) %>% lapply(fast_tune, um))
                  },
              fine = {
                  Map(function(x, y) x %>% add_column(y),
                      mem, mem %>% lapply(`[[`, 3) %>% lapply(fine_tune, um))
                  },
              kmeans = {
                  Map(function(x, y) x %>% add_column(y),
                      mem, mem %>% lapply(`[[`, 3) %>% lapply(kmeans_int, um))
                  },
              stop("Invalid tuning input")
          )
        )
      res <- res %>% mutate(modularity_up    = map_dbl(cluster, ~ mod_cal(.x$label_up))
                           ) %>% arrange(desc(modularity_up))        
    # res <- res %>%
    #               mutate(label_up         = map(k, ~ kmeans(um, .x)$cluster),
    #                      modularity_up    = map_dbl(label_up, ~ mod_cal(.x))
    #                      ) %>% arrange(desc(modularity_up))
    } else {
      # unweighted graph
      if (missing(tune)) {
          tune <- "fine"
      }
      if (dim == 1) {
        label       <- rep(1, n)
        modularity  <- mod_cal(mem = label)
        mem_time    <- tune_time <- 0
        res         <- tibble(k = 1, modularity_up = modularity)
        res$cluster <- list(tibble(mem_up = 1,
                                   mem_norm_up = 1,
                                   label_up = label))
      } else if (dim == 2) {
        label <- (1 + sign(u[, 1])) / 2
        modularity <- mod_cal(mem = label)
        mem_time    <- tune_time <- 0
        res <- tibble(k = 2, modularity_up = modularity)
        res$cluster <- list(tibble(mem_up = u[, 1],
                                   mem_norm_up = SoftMax(u[, 1]),
                                   label_up = label))
      } else {
        r <- u[, seq_len(dim)] %*% diag(sqrt(lambda[seq_len(dim)]))
        cosine_time <- system.time(suppressMessages(
        gd <- as_tibble(
              foreach(i = seq_len(nrow(eclidean)), .combine = rbind) %dopar%
                apply(u[, seq_len(dim)], 2, function(x)
                  cosine(eclidean[i, ], x)
                ),
              .name_repair = "unique")))
        res <- tibble(k = switch(2 - is.null(kopt),
                                 seq_len(ncol(gd)),
                                 kopt),
                      modularity = 0)
        mem_time  <- system.time(mem <- mem_cal(gd, kopt = kopt))
        tune_time <- system.time(
          res$cluster <- switch(tune,
              fast = {
                  Map(function(x, y) x %>% add_column(y),
                      mem, mem %>% lapply(`[[`, 3) %>% lapply(fast_tune, r))
                  },
              fine = {
                  Map(function(x, y) x %>% add_column(y),
                      mem, mem %>% lapply(`[[`, 3) %>% lapply(fine_tune, r))
                  },
              kmeans = {
                  Map(function(x, y) x %>% add_column(y),
                      mem, mem %>% lapply(`[[`, 3) %>% lapply(kmeans_int, r))
                  },
              stop("Invalid tuning input")
          )
        )
        # output result
        res <- res %>%
               mutate(modularity    = map_dbl(cluster,
                                              ~ mod_cal(.x$label)),
                      k_up          = map_dbl(cluster,
                                              ~ length(unique(.x$label_up))),
                      modularity_up = map_dbl(cluster,
                                              ~ mod_cal(.x$label_up))
                      ) %>% arrange(desc(modularity_up))
      }
  }
    return(res)
}
