#! /usr/bin/env python3
from argparse import ArgumentParser
import requests


def main():
    parser = ArgumentParser(description="Configure Graylog")
    parser.add_argument(
        "--url",
        type=str,
        default="http://localhost",
        help="URL of the Graylog server (Default: http://localhost)"
    )
    parser.add_argument(
        "--port",
        type=str,
        default="9000",
        help="URL of the Graylog server (Default: 9000)"
    )
    parser.add_argument(
        "--admin-password",
        type=str,
        required=True,
        help="Password for the Graylog admin account",
    )
    args = parser.parse_args()

    api = GraylogAPI(**vars(args))

    inputs = api.get_inputs()
    print(inputs)
    if inputs["total"] > 0:
        api.delete_all_inputs(inputs["inputs"])
    api.add_syslog_input()


class GraylogAPI(object):
    def __init__(self, url, port, admin_password):
        self.api_root = f"{url}:{port}/api"
        self.username = "admin"
        self.password = admin_password
        self.headers = {"X-Requested-By": "admin"}

    @property
    def auth(self):
        return requests.auth.HTTPBasicAuth(self.username, self.password)

    def get_inputs(self):
        response = requests.get(
            f"{self.api_root}/system/inputs",
            auth=self.auth
        )

        code = response.status_code

        if code == 200:
            return response.json()
        else:
            print(f"Failed to get inputs.\nStatus code:{code}")

    def delete_all_inputs(self, inputs):
        for _input in inputs:
            print(_input["id"])
            response = requests.delete(
                f"{self.api_root}/system/inputs/{_input['id']}",
                auth=self.auth,
                headers=self.headers
            )

            code = response.status_code

            if code == 204:
                print(f"Successfully deleted input {_input['title']}")
            else:
                print(f"Failed to delete input {_input['title']}."
                      f"\nStatus code: {code}")
                print(response.content)

    def add_syslog_input(self):
        payload = {
            "title": "Syslog input",
            "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput",
            "global": True,
            "configuration": {
                "bind_address": "0.0.0.0",
                "port": 1514,
                "tls_enable": False,
                "tcp_keepalive": False,
                "use_null_delimiter": False,
                "force_rdns": False,
                "allow_override_date": True,
                "store_full_message": False,
                "expand_structured_data": False
            }
        }

        response = requests.post(
            f"{self.api_root}/system/inputs",
            auth=self.auth,
            headers=self.headers,
            json=payload
        )

        code = response.status_code

        if code == 201:
            print("Syslog input successfully created")
        elif code == 400:
            print("Syslog input already exists or missing/invalid configuration")
            print(response.content)
        else:
            print(f"Syslog input creation failed.\nStatus code: {code}")


if __name__ == "__main__":
    main()
