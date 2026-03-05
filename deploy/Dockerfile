FROM barichello/godot-ci:4.6 AS builder

COPY godot/point_cloud /godot_project

# Verify Godot version matches the project
RUN PROJECT_VERSION=$(grep 'config/features' /godot_project/project.godot | grep -oP '\d+\.\d+') && \
    GODOT_VERSION=$(godot --version | grep -oP '^\d+\.\d+') && \
    if [ "$PROJECT_VERSION" != "$GODOT_VERSION" ]; then \
        echo "ERROR: Godot version mismatch! Project: $PROJECT_VERSION, Docker: $GODOT_VERSION" && exit 1; \
    fi

RUN cd /godot_project && godot --headless --verbose --export-release "Web" /web_export/index.html;

FROM nginx:alpine

COPY --from=builder /web_export /usr/share/nginx/html/

COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80