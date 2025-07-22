FROM ghcr.io/zabdelillah/ffmpeg:gl-transitions
COPY "wrapper.sh" "/wrapper.sh"
COPY "ffmpegwrapper.sh" "/ffmpegwrapper.sh"
RUN chmod +x /*.sh; dnf install -y jq xorg-x11-server-Xvfb git; \
	git clone https://github.com/gl-transitions/gl-transitions.git; \
	for file in transitions/*.glsl; do \
		if grep -Eq '^uniform.*//\s.*[0-9]+$' "$file"; then \
			export matched_line=$(grep -E '^uniform.*[0-9]+$' "$file" | head -n1); \
			sed -i.bak "\|${matched_line}|d" "$file"; \
			export var=$(echo "$matched_line" | grep -Eo '^uniform\s+[a-zA-Z]+\s+[a-zA-Z_][a-zA-Z0-9_]*' | awk '{print $3}'); \
			export val=$(echo "$matched_line" | grep -Eo '[0-9\.]+$'); \
			sed -i.bak "\|${matched_line}|d" "$file"; \
			sed -i.bak "s/${var}/\(${val}\)/g" "$file"; \
			rm "${file}.bak"; \
		fi; \
	  fi; \
	done; \
	mv gl-transitions/transitions/* ./;
ENTRYPOINT ["/wrapper.sh"]