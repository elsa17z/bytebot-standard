# ByteBot Standard Image

**Public Docker image containing desktop environment + standard bytebotd**

## What's Inside

### Desktop Environment
- Ubuntu 22.04
- XFCE4 desktop
- Firefox ESR, Thunderbird
- 1Password, VSCode
- X11, VNC, noVNC

### Standard ByteBot
- NestJS framework
- Anthropic MCP tools
- Computer-use tools
- Input tracking
- Custom libnut

## What's NOT Inside

**Computer-control module** - This proprietary module is built separately from a private repo

## Usage

This image is designed to be extended by adding the computer-control module:

```dockerfile
FROM ghcr.io/elsa17z/bytebot-standard:latest

# Add computer-control module
COPY packages/bytebotd/src/computer-control/ /bytebot/bytebotd/src/computer-control/
COPY packages/bytebotd/src/app.module.ts /bytebot/bytebotd/src/

# Rebuild with custom module (2 min)
RUN npm run build

EXPOSE 9990
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
```

## Build Info

- **Build time:** ~18 minutes
- **Image size:** ~2 GB
- **Rebuild frequency:** Weekly (automated)
- **Registry:** ghcr.io/elsa17z/bytebot-standard:latest

## Privacy

This image is PUBLIC and contains no proprietary code:
- ✅ Open-source desktop applications
- ✅ Open-source frameworks and libraries
- ✅ Standard Anthropic MCP implementation
- ❌ NO proprietary computer-control code

## License

MIT License - Standard open-source components only
