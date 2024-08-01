import logging
from typing import Any

import azure.functions as func
import requests

app = func.FunctionApp()

# Global parameters
# gitea_host = "http://gitea_mirror.local"
gitea_host = "http://localhost:3000"
api_root = "/api/v1"
migrate_path = "/repos/migrate"
repos_path = "/repos"
timeout = 60


def get_args(args: list[str], req: func.HttpRequest) -> dict[str, str | None]:
    try:
        req_body = req.get_json()
    except ValueError:
        return {}

    args_dict = {arg: str_or_none(req_body.get(arg)) for arg in args}
    logging.info(f"Parameters: {args}.")
    return args_dict


def str_or_none(item: Any) -> str | None:
    return str(item) if item is not None else None


def check_args(args: dict[str, str | None]) -> dict[str, str] | None:
    if None in args.values():
        return None
    else:
        return {key: str(value) for key, value in args.items()}


def missing_parameters_repsonse() -> func.HttpResponse:
    msg = "Required parameter not provided."
    logging.critical(msg)
    return func.HttpResponse(
        msg,
        status_code=400,
    )


def handle_response(
    response: requests.Response, valid_codes: list[int], error_message: str
) -> func.HttpResponse | None:
    logging.info(f"Response status code: {response.status_code}.")
    logging.debug(f"Response contents: {response.text}.")
    if response.status_code not in valid_codes:
        return func.HttpResponse(
            error_message,
            status_code=400,
        )
    else:
        return None
