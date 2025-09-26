FROM debian:13 AS build
WORKDIR /app
COPY ./ ./
RUN apt update && apt install -y curl git
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup && forge doc --build


FROM nginx:latest
COPY --from=build /app/docs/book /usr/share/nginx/html
