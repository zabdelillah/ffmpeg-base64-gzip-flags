FROM linuxserver/ffmpeg:7.1.1
COPY "wrapper.sh" "/wrapper.sh"
RUN chmod +x /wrapper.sh
ENTRYPOINT ["/wrapper.sh"]