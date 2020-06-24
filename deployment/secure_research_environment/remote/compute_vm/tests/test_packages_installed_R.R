library(stringr)

# Initialise lists
warning_list <- c()
error_list <- c()

# The following packages give errors that are false positives
# BiocManager: False positive - warning about not being able to connect to the internet
# clusterProfiler: Error is "multiple methods tables found for 'toTable'". Not yet understood
# flowUtils: False positive - warning about string translations
# GOSemSim: False positive - no warning on package load
# graphite: False positive - no warning on package load
# rgl: Error is because the X11 server could not be loaded
# tmap: False positive - no warning on package load
# BiocInstaller: False positive - warning about not being able to connect to the internet
# others: False positive - package not included in VM image 0.2.2020060100
false_positive_list <- c("BiocManager", "clusterProfiler", "flowUtils", "GOSemSim", "graphite", "rgl", "tmap", "BiocInstaller", "COMBAT", "RMariaDB", "RPostgres", "GlobalAncova", "GO", "GSVA", "MassSpecWavelet", "moe430a")


# Test package with non-standard evaluation and append to the proper list
test_package <- function(p) {
    tryCatch(
        eval(parse(text = paste0("library(", p, ")"))),
        error = function(m) {
            assign("error_list", c(error_list, p), envir = .GlobalEnv)
        },
        warning = function(m) {
            assign("warning_list", c(warning_list, p), envir = .GlobalEnv)
        },
        message = function(m) {
            # do nothing, as many packages print messages upon loading
        }
    )
}

# Read in the package list from the repo
repos <- c("CRAN", "Bioconductor")
n_packages = 0
for (repo in repos) {
    packageList = file.path("..", "package_lists", paste("packages-r-", tolower(repo), ".list", sep = ""))
    packages <- readLines(packageList)
    print(paste("Testing", length(packages), repo, "packages"))
    for (package in packages) {
        if (!(package %in% false_positive_list)) {
            test_package(package)
        }
    }
    n_packages = n_packages + length(packages)
}

# Show results
if (0 == length(warning_list) & 0 == length(error_list)) {
    print(paste("All", n_packages, "package(s) OK!"))
} else {
    # List any warnings
    if (0 < length(warning_list)) {
        print(paste("The following", length(warning_list), "packages gave a warning:"))
        cat(warning_list, sep = "\n")
    }
    # List any errors
    if (0 < length(error_list)) {
        print(paste("The following", length(error_list), "packages gave a error:"))
        cat(error_list, sep = "\n")
    }
}
