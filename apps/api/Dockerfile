FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download || true
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/api ./...

FROM hashicorp/vault:1.18
COPY --from=build /out/api /api
COPY agent.hcl /etc/vault/agent.hcl
RUN echo -n "root" > /etc/vault/token
EXPOSE 3000
ENTRYPOINT ["vault", "agent", "-config=/etc/vault/agent.hcl"]
