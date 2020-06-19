import requests


def http_error(msg, response):
    return requests.HTTPError(
        msg + ": Unexpected response: " + response.reason + " ("
        + response.status_code + "), content: " + resonse.text
    )
