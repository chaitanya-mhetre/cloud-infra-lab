# Optional all-in-one toolbox with the same pinned versions make/CI use.
#   docker build -t cil-toolbox . && docker run --rm -it -u "$(id -u):$(id -g)" -v "$PWD:/repo" -w /repo cil-toolbox make check TOOLS=scripts/local-tools.sh
# (`make check` doesn't need this: it runs each tool from its own official image via scripts/tools.sh.)
FROM alpine:3.20
ARG TERRAFORM_VERSION=1.9.8
ARG TFLINT_VERSION=0.53.0
ARG HELM_VERSION=3.16.2
ARG KUBECTL_VERSION=1.31.2
ARG KUBECONFORM_VERSION=0.6.7
RUN apk add --no-cache bash curl git jq make unzip python3 py3-pip aws-cli shellcheck \
 && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/tf.zip \
 && unzip /tmp/tf.zip -d /usr/local/bin && rm /tmp/tf.zip \
 && curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" -o /tmp/tfl.zip \
 && unzip /tmp/tfl.zip -d /usr/local/bin && rm /tmp/tfl.zip \
 && curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm \
 && curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
 && curl -fsSL "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" | tar xz -C /usr/local/bin \
 && chmod +x /usr/local/bin/kubectl \
 && pip install --no-cache-dir --break-system-packages checkov \
 && adduser -D -u 10001 ops
USER ops
WORKDIR /repo
