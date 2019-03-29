# Generate random data from clusters
num_clusters <- 5
N <- 10
set.seed(0, kind = "Mersenne-Twister")
cluster_means <- runif(num_clusters, 0, 10)
means_selector <- as.integer(runif(N, 1, num_clusters+1))
data_means <- cluster_means[means_selector]
data <- rnorm(n = N, mean = data_means, sd = 0.5)

# Run hclust algorithm
hc <- hclust(dist(data))
if ("ggdendro" %in% installed.packages()) {
  library(ggdendro)
  library(ggplot2)
  p  <- ggdendrogram(hc, rotate = TRUE)

  # Write plot to disk
  ggsave("dendrogram.png", p, width = 16, height = 9)
}
