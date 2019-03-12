# Kontena Mortar

![Mortar - Manifest shooter for Kubernetes](kontena-mortar.png)

Mortar is a tool to easily handle a complex set of Kubernetes resources. Using `kubectl apply -f some_folder/` is pretty straightforward for simple cases, but often, especially in CI/CD pipelines things get complex. Then on the otherhand, writing everything in Helm charts is way too complex.

While we were developing [Kontena Pharos](https://kontena.io/pharos) Kubernetes distro and tooling around it, we soon realized that we really want to manage sets of resources as a single unit. This thinking got even stronger while we were transitioning many of our production solutions to run on top of Kubernetes. As this is a common problem for all Kubernetes users, Mortar was born.

## Features

- [Management of sets of resources as a single unit](#shots)
- [Simple templating](#templating)
- [Overlays](#overlays)

## Installation

### Binaries

Mortar pre-baked binaries are available for OSX and Linux. You can download them from the [releases](https://github.com/kontena/mortar/releases) page. Remember to put it in the path and change the executable bit on.

### MacOS Homebrew

`$ brew install kontena/mortar/mortar`

Or to install the latest development version:

`$ brew install --HEAD kontena/mortar/mortar`

### Rubygems:

`$ gem install kontena-mortar`

To install bash/zsh auto-completions, use `mortar install-completions` after Mortar has been installed.

### Docker:

`$ docker pull quay.io/kontena/mortar:latest`


## Usage

### Configuration

By default mortar looks for if file `~/.kube/config` exists and uses it as the configuration. Configuration file path can be overridden with `KUBECONFIG` environment variable.

For CI/CD use mortar also understands following environment variables:

- `KUBE_SERVER`: kubernetes api server address, for example `https://10.10.10.10:6443`
- `KUBE_TOKEN`: service account token (base64 encoded)
- `KUBE_CA`: kubernetes CA certificate (base64 encoded)

### Deploying k8s yaml manifests

```
$ mortar fire [options] <src-folder> <shot-name>
```

### Removing a deployment

```
$ mortar yank [options] <shot-name>
```

### Listing all shots

```
$ mortar list [options]
```

### Describing a shot

```
$ mortar describe [options] <shot-name>
```

### Docker image

You can use mortar in CI/CD pipelines (like Drone) via `quay.io/kontena/mortar:latest` image.

Example config for Drone:

```yaml
pipeline:
  deploy:
    image: quay.io/kontena/mortar:latest
    secrets: [ kube_token, kube_ca, kube_server ]
    commands:
      - mortar fire k8s/ my-app

```

## Namespaces

**Namespace is mandatory to be set on the resources**

Currently Mortar will not add any default namespaces into the resources it shoots. Therefore it is mandatory for the user to set the namespaces in all namespaced resources shot with Mortar. See [this](https://github.com/kontena/mortar/issues/10) issue for details and track the fix.

## Shots

Mortar manages a set of resources as a single unit, we call them *shots*. A shot can have as many resources as your application needs, there's no limit to that. Much like you'd do with `kubectl apply -f my_dir/`, but Mortar actually injects information into the resources it shoots into your Kubernetes cluster. This added information, labels and annotations, will be used later on by Mortar itself or can be used with `kubectl` too. This allows the management of many resources as a single application.

Most importantly, Mortar is able to use this information when re-shooting your applications. One of the most difficult parts when using plain `kubectl apply ...` approach is the fact that it's super easy to leave behind some lingering resources. Say you have some `deployments` and a `service` in your application, each defined in their own `yaml` file. Now you remove the service and re-apply with `kubectl apply -f my_resources/`. The service will live on in your cluster. With Mortar, you don't have to worry. With the extra labels and annotations Mortar injects into the resources, it's also able to automatically prune the "un-necessary" resources from the cluster. The automatic pruning is done with `--prune` option.

See basic example [here](/examples/basic).

## Overlays

One of the most powerful features of Mortar is it's ability to support *overlays*. An overlay is a variant of the set of resources you are managing. A variant might be for example the same application running on many different environments like production, test, QA an so on. A variant might also be a separate application "instance" for each customer. Or what ever the need is. Overlays in Mortar are inspired by [kustomize](https://github.com/kubernetes-sigs/kustomize).

Given a folder & file structure like:
```
echoservice-metallb/
├── echo-metal.yml
├── foo
│   └── pod.yml.erb
└── prod
    ├── pod.yml
    └── svc.yml
```

where overlays (`prod` & `foo`) contain same resources as the base folder, mortar now merges all resources together. Merging is done in the order overlays are given in the command. Resources are considered to be the same resource if all of these match: `kind`, `apiVersion`, `metadata.name` and `metadata.namespace`.

If there are new resources in the overlay dirs, they are taken into the shot as-is.

You'd select overlays taken into processing with `--overlay option`.

**Note:** Overlays are taken in in the order defined, so make sure you define them in correct order.

The resources in the overlays do not have to be complete, it's enough that the "identifying" fields are the same.

See example of overlays [here](/examples/overlays).

## Templating

Mortar also support templating for the resource definitons. The templating language used is [ERB](https://en.wikipedia.org/wiki/ERuby). It's pretty simple templating language but yet powerful enough for Kubernetes resource templating.

**Note:** Mortar will process the resource definitions as ERB even if the filename does not have the `.erb` extension. This means that Ruby code in an innocent looking `.yml` file will be evaluated using the current user's access privileges on the local machine. Running untrusted code is dangerous and so is deploying untrusted manifests, make sure you know what you're deploying.

### Variables

There are two ways to introduce variables into the templating.

See examples at [examples/templates](examples/templates).

#### Environment variables

As for any process, environment variables are also available for Mortar during template processing.

```yaml
kind: Pod
apiVersion: v1
metadata:
  name: nginx
  labels:
    name: nginx
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:<%= ENV["NGINX_VERSION"] || "latest" %>
    ports:
      - containerPort: 80
```

#### Variables via options

Another option to use variables is via command-line options. Use `mortar --var foo=bar my-app resources/`.

Each of the variables defined will be available in the template via `var.<variable name>`.

```yaml
kind: Pod
apiVersion: v1
metadata:
  name: nginx
  labels:
    name: nginx
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
      - containerPort: <%= port.number %>
        name: <%= port.name %>
```

You could shoot this resource with `mortar --var port.name=some-port --var port.number=80 my-app resources/pod.yml.erb`

### Shot configuration file

It is also possible to pass [variables](#variables), [overlays](#overlays) and [labels](#labels) through a configuration file. As your templates complexity and the amount of variables used grows, it might be easier to manage the variables with an yaml configuration file. The config file has the following syntax:

```yaml
variables:
  ports:
    - name: http
      number: 80
    - name: https
      number: 443
overlays:
  - foo
  - bar
```

`variables`, `overlays` and `labels` are optional.

For variables the hash is translated into a `RecursiveOpenStruct` object. What that means is that you can access each element with dotted path notation, just like the vars given through `--var` option. And of course arrays can be looped etc.. Check examples folder how to use variables effectively.

The configuration file can be given using `-c` option to `mortar fire` command. By default Mortar will look for `shot.yml` or `shot.yaml` files present in current working directory.

### Labels

It's possible to set global labels for all resources in a shot via options or configuration file.

#### Labels via options

Use `mortar --label foo=bar my-app resource` to set label to all resources in a shot.

#### Labels via configuration file

```yaml
labels:
  foo: bar
  bar: baz
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kontena/mortar.

## License

Copyright (c) 2018 Kontena, Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
