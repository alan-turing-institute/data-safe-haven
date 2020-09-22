# Tier1 Secure Research Environment User Documentation

## Contents

## :seedling: Prerequisites

- An SSH client. This should be installed by default on OSX, Linux, BSD. For
  Windows, options include [PuTTY](https://putty.org/) and
  [MobaXterm](https://mobaxterm.mobatek.net/).
- An authenticator app with support for TOTP passwords such as
  [andOTP](https://github.com/andOTP/andOTP) (or if without a smartphone, a way
  to generate OTP codes from your secret `i.e.` oathtool)

## Account Setup

- Generate an ssh key pair if you do not already have one. On OSX/Linux
  `ssh-keygen -t rsa -b 4096 -f tier1`. On Windows ???
- Send the **public part** of your key pair to ??? (using the above command this
  will be called `tier1.pub`.
- After your account is created you will be sent an image of a QR code and your
  username. Scan this code using your authenticator app as you will need a
  corresponding one-time password to login.

## Authentication

- You will connect to the VM by SSH. To authenticate you will need
  - Your username
  - Your private key
  - Your authenticator app configured with your QR code
  - The IP address of the VM
- In order to access CoCalc you will create an SSH tunnel, which connects your
  local machine to the CoCalc service on the VM via an encrypted connection.
- On OSX/Linux connect with `ssh <username>@<vm-ip-address> -i
  <path-to-private-key> -L 8443:localhost:443`
> The flag and argument `-L 8443:localhost:443` connects port 8443 on your local
> machine to port 443 on the VM via an SSH tunnel. Port 443 is where CoCalc is
> served on the VM. Hence, you will be able to access CoCalc on
> `localhost:8443`.
- If public key authentication is succcesful, you will be prompted for a
  one-time password ``One-time password (OATH) for `<username>':``. At this
  point you should generate a one-time using your authenticator app, which
  should be six numbers, and enter it.
- If everything was correct you will now have a shell in the VM.

## Connecting to CoCalc

- After an SSH tunnel has been created you can access CoCalc in a browser.
- Open your browser and navigate to `https://localhost:8443`. Note that it is
  necessary to use `https` rather than `http`.
- The first time you connect you will likely see a warning that the certificate
  is not valid. This is expected as it is not possible to generate a certificate
  for `localhost`. You can safely add an exception and bypass this warning.

## Using CoCalc

- Detailed documentation for using CoCalc can be found
  [here](https://doc.cocalc.com/docker-image.html).
- In the rest of this documentation we will try to address some common
  questions.

## Inviting Users to Projects

## Installing Python Packages

## Accessing Project Data
### Read-only Data
### OutPuts
