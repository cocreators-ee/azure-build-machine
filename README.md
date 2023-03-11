# Build machine setup tool

Supports agents for

- Azure DevOps
- Jetbrains Space

Scripts to set up a lot of things you need for a decent build machine all in one go

**Quickstart:**

```bash
wget https://raw.githubusercontent.com/cocreators-ee/build-machine/master/setup.sh -O - | sudo bash
```

**Also install Azure DevOps agents**:

```bash
wget https://raw.githubusercontent.com/cocreators-ee/build-machine/master/setup.sh -O - | sudo bash -s -- \
  --azure-org your_devops_org \
  --azure-agent-count 2 \
  --azure-pat your_personal_access_token
```

**After `setup.sh` you can also install JetBrains Space workers**:

```bash
wget https://raw.githubusercontent.com/cocreators-ee/build-machine/master/setup_space_worker.sh -O - | sudo bash -s -- \
  --serverUrl https://your_org.jetbrains.space \
  --token abc123 \
  --name your_worker_name
```

For JetBrains Space you need to first go to Administration -> Automation -> Add worker, to get the token. You can run the script multiple times if you want to register multiple workers on the same machine, just keep the names unique. 

But really, don't run this unless you really have read and understand [setup.sh](./setup.sh). What you should do is fork
this repo, customize the script, and the command above to point to your repo, and then use that one instead.


## Quick explanation

Assuming an installed Ubuntu 20.04 base this sets up:

 - A recognizable hostname
 - Some `dpkg` configuration to make things more reliable and fast (disable man, etc.)
 - Unattended upgrades
 - Configures `apt` to use local mirrors
 - Installs various common utilities you need for most things (curl, git, wget, ...)
 - Sets up the repos to install Docker, Node, Python, Azure CLI, Google Cloud SDK, .NET Core and maybe a few other things that I forgot to add here
 - Installs those things
 - Installs some additional build tools you regularly need to install anything else like g++, gcc, make, ...
 - Recent Python + Poetry + pre-commit + pipx
 - Recent Node + pnpm + firebase-tools
 - OpenJDK
 - Git username and email to something predictable
 - Some custom tools (gcrc)
 - Allows SSH through the firewall and nothing else
 - Enables Google Cloud Firestore emulator as a service

May also be used to set up:
 - [Azure Pipelines Agent](https://github.com/microsoft/azure-pipelines-agent)
 - [JetBrains Space Worker](https://www.jetbrains.com/help/space/run-steps-in-external-workers.html)

Now if this list didn't convince you that you should customize this to YOUR needs, well you probably shouldn't be using this tool.


## Testing locally

Easiest most generic option is to install [Vagrant](https://www.vagrantup.com), and then run:

```bash
vagrant up
vagrant ssh
sudo -i
cd /src
bash setup.sh \
 ... those args from above ...
```


# License

Short answer: This software is licensed with the BSD 3-clause -license.

Long answer: The license for this software is in [LICENSE.md](./LICENSE.md), the other pieces of software installed and used have varying other licenses that you need to be separately aware of.


# Financial support

This project has been made possible thanks to [Cocreators](https://cocreators.ee) and [Lietu](https://lietu.net). You can help us continue our open source work by supporting us on [Buy me a coffee](https://www.buymeacoffee.com/cocreators).

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/cocreators)
