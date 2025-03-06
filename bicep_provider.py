"""Executes the commands configured in provider.yaml."""

import json
import os
import subprocess
import sys
import getpass

def run(cmd):
    print(f"Running: {cmd}", file=sys.stderr)
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True).stdout
    except subprocess.SubprocessError as e:
        print("Subprocess error:", file=sys.stderr)
        for attr, value in e.__dict__.items():
            print(f"{attr}: {value}", file=sys.stderr)
        raise

# The environment variables are set by DevPod.
# region = os.environ["AZURE_REGION"]
bicep = os.environ["BICEP_FILE"]
cmd = sys.argv[1]

if cmd == "create":
    folder = os.environ["MACHINE_FOLDER"]
    machine = os.environ["MACHINE_ID"]
    vmSize = os.environ['VM_SIZE']
    diskSize = os.environ['DISK_SIZE']
    rg = os.environ["AZURE_RESOURCE_GROUP"]
    user =  getpass.getuser()
    dockerUsername = os.environ['GHCR_USERNAME']
    dockerToken = os.environ['GHCR_TOKEN']

    print(f"Creating machine {machine} with user {user}")

    # Generate ssh key
    run(f"ssh-keygen -f {folder}/key")
    with open(f"{folder}/key.pub", 'r') as f:
        pubkey = f.read()

    # Create deployment stack
    result = run("az stack group create "
        f"--name devpod-{machine} "
        f"--resource-group '{rg}' "
        f"--template-file '{bicep}' "
        "--action-on-unmanage 'DeleteAll' "
        "--deny-settings-mode 'none' "
        f"--parameters 'adminPasswordOrKey={pubkey}' "
        f"--parameters 'vmName=devpod-{machine}' "
        f"--parameters 'adminUsername={user}' "
        f"--parameters 'vmSize={vmSize}' "
        f"--parameters 'diskSize={diskSize}' "
        f"--parameters 'dockerUsername={dockerUsername}' "
        f"--parameters 'dockerToken={dockerToken}' "
        "--yes")

    result = json.loads(result)
    hostname = result["outputs"]["hostname"]["value"]
    print(f"Created vm with hostname {hostname}")
    with open(f"{folder}/host", 'w') as f:
        f.write(hostname)

elif cmd == "delete":
    machine = os.environ["MACHINE_ID"]
    rg = os.environ["AZURE_RESOURCE_GROUP"]
    run(
        "az stack group delete "
        f"--name 'devpod-{machine}' "
        f"--resource-group '{rg}' "
        "--action-on-unmanage 'deleteAll' "
        "--yes"
    )
elif cmd == "command":
    folder = os.environ["MACHINE_FOLDER"]
    machine = os.environ["MACHINE_ID"]
    command = os.environ["COMMAND"]

    with open(f"{folder}/host", 'r') as f:
        host = f.read()

    print(f"running command {command} on machine {machine} folder {folder} host {host}", file=sys.stderr)

    subprocess.run(
        [
            "ssh",
            "-o",
            "StrictHostKeyChecking=accept-new",
            f"{host}",
            "-i",
            f"{folder}/key",
            command,
        ],
        check=True,
        stdin=sys.stdin,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )
elif cmd == "status":
    rg = os.environ["AZURE_RESOURCE_GROUP"]
    machine = os.environ["MACHINE_ID"]
    status = run(
        f"az vm get-instance-view --resource-group {rg} --name devpod-{machine} --query 'instanceView.statuses[1].code' || echo 'not found'"
    ).strip()
    if status == "not found":
        print("NotFound")
    else:
        if status == '"PowerState/running"':
            print("Running")
        elif status == '"PowerState/deallocated"':
            print("Stopped")
        else:
            print("Busy")
elif cmd == "stop":
    rg = os.environ["AZURE_RESOURCE_GROUP"]
    machine = os.environ["MACHINE_ID"]
    run(f"az vm deallocate --name devpod-{machine} --resource-group {rg}")
elif cmd == "start":
    rg = os.environ["AZURE_RESOURCE_GROUP"]
    machine = os.environ["MACHINE_ID"]
    run(f"az vm start --name devpod-{machine} --resource-group {rg}")
elif cmd == "test":
    run(f"error")