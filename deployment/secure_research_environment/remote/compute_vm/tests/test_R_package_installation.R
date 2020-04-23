library(stringr)

# Initialise lists
warning_list <- c()
error_list <- c()

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
for (repo in repos) {
    packageList = file.path("..", "package_lists", paste("r", tolower(repo), "packages.list", sep = "-"))
    packages <- readLines(packageList)
    print(paste("Testing", length(packages), repo, "packages"))
    for (package in packages) {
        test_package(package)
    }
}

# Show results
if (0 == length(warning_list) & 0 == length(error_list)) {
    print(paste("All ", length(packages), " package(s) OK!"))
} else {
    if (0 < length(warning_list)) {
        print(paste("The following", length(warning_list), "packages gave a warning:", sep = " "))
        cat(warning_list, sep = "\n")
    }

    if (0 < length(error_list)) {
        print(paste("The following", length(error_list), "packages gave a error:", sep = " "))
        cat(error_list, sep = "\n")
    }
}
