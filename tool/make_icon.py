"""Draw the app's simple waveform icon without external image dependencies."""
import pathlib, struct, zlib

def png(size):
    scale=4
    n=size*scale
    pixels=[]
    for y in range(n):
        row=[]
        for x in range(n):
            u=(x+.5)/n;v=(y+.5)/n
            qx=max(.18-u,0,u-.82);qy=max(.18-v,0,v-.82)
            inside=qx*qx+qy*qy<.18*.18
            rgb=(191,100,45,255) if inside else (0,0,0,0)
            for cx,height in [(.27,.21),(.385,.43),(.5,.62),(.615,.38),(.73,.19)]:
                dx=max(abs(u-cx)-.022,0);dy=max(abs(v-.5)-(height/2-.022),0)
                if inside and dx*dx+dy*dy<.022*.022:rgb=(255,255,255,255)
            row.append(rgb)
        pixels.append(row)
    raw=bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            for channel in range(4):raw.append(round(sum(pixels[y*scale+j][x*scale+i][channel] for j in range(scale) for i in range(scale))/(scale*scale)))
    def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(raw)))+chunk(b'IEND',b'')

root=pathlib.Path(__file__).resolve().parents[1]
sizes=[16,32,48,256];images=[png(s) for s in sizes];offset=6+16*len(sizes)
header=struct.pack('<HHH',0,1,len(sizes))
for size,image in zip(sizes,images):
    header+=struct.pack('<BBBBHHII',size%256,size%256,0,0,1,32,len(image),offset);offset+=len(image)
(root/'windows/runner/resources/app_icon.ico').write_bytes(header+b''.join(images))
