FROM debian:13 as build
COPY ./ ./
RUN apt update && apt install -y curl git
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup && forge doc --build


FROM nginx:latest
COPY --from=build /docs/book /usr/share/nginx/html
