#!/usr/bin/env python3
"""Repair the Godot APK template's duplicate Startup/FileProvider authority.

Preserves all manifest attributes except InitializationProvider.authorities.
Run before zipalign and signing; the old APK signature becomes invalid.
"""
import argparse,struct,zipfile
from pathlib import Path


def u16(data,pos):return struct.unpack_from('<H',data,pos)[0]
def u32(data,pos):return struct.unpack_from('<I',data,pos)[0]
def length8(data,pos):
    first=data[pos]
    return (((first&127)<<8)|data[pos+1],pos+2) if first&128 else (first,pos+1)
def length16(data,pos):
    first=u16(data,pos)
    return (((first&32767)<<16)|u16(data,pos+2),pos+4) if first&32768 else (first,pos+2)


def repair(data,authority):
    assert u16(data,0)==3 and u32(data,4)==len(data),'Not a binary Android manifest'
    chunks=[];pos=u16(data,2);strings=[];new_index=None;changed=0
    while pos<len(data):
        kind,header,size=struct.unpack_from('<HHI',data,pos)
        chunk=bytearray(data[pos:pos+size]);assert len(chunk)==size
        if kind==1:
            count,styles,flags,start,style_start=struct.unpack_from('<IIIII',chunk,8)
            utf8=bool(flags&256)
            for i in range(count):
                p=start+u32(chunk,header+i*4)
                if utf8:
                    _,p=length8(chunk,p);n,p=length8(chunk,p);strings.append(bytes(chunk[p:p+n]).decode('utf-8'))
                else:
                    n,p=length16(chunk,p);strings.append(bytes(chunk[p:p+n*2]).decode('utf-16le'))
            new_index=count
            encoded=authority.encode('utf-8' if utf8 else 'utf-16le')
            assert len(authority)<128 and len(encoded)<128
            encoded=(bytes([len(authority),len(encoded)])+encoded+b'\0') if utf8 else (struct.pack('<H',len(authority))+encoded+b'\0\0')
            old_strings=bytes(chunk[start:style_start if style_start else size])
            payload=old_strings+encoded
            payload+=b'\0'*(-len(payload)%4)
            new_start=start+4
            new_style_start=new_start+len(payload) if style_start else 0
            result=bytearray(chunk[:header])
            result+=chunk[header:start]
            # Insert a final string offset before any style offsets.
            split=header+count*4
            result=result[:split]+struct.pack('<I',len(old_strings))+result[split:]
            result+=payload
            if style_start:result+=chunk[style_start:]
            struct.pack_into('<I',result,4,len(result))
            struct.pack_into('<I',result,8,count+1)
            struct.pack_into('<I',result,20,new_start)
            struct.pack_into('<I',result,24,new_style_start)
            chunk=result
        elif kind==0x102 and strings:
            node_name=strings[u32(chunk,20)]
            if node_name=='provider':
                attr_start=16+u16(chunk,24);attr_size=u16(chunk,26);count=u16(chunk,28)
                attrs={strings[u32(chunk,attr_start+i*attr_size+4)]:attr_start+i*attr_size for i in range(count)}
                name_pos=attrs.get('name');authority_pos=attrs.get('authorities')
                if name_pos is not None and authority_pos is not None:
                    name=strings[u32(chunk,name_pos+16)]
                    if name=='androidx.startup.InitializationProvider':
                        assert chunk[authority_pos+15]==3
                        struct.pack_into('<I',chunk,authority_pos+8,new_index)
                        struct.pack_into('<I',chunk,authority_pos+16,new_index)
                        changed+=1
        chunks.append(bytes(chunk));pos+=size
    assert changed==1,f'Expected one InitializationProvider, got {changed}'
    result=bytearray(data[:u16(data,2)]+b''.join(chunks))
    struct.pack_into('<I',result,4,len(result))
    return bytes(result)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--authority',default='org.lumaradio.commandcenter.androidx-startup')
    args=parser.parse_args()
    with zipfile.ZipFile(args.source) as src,zipfile.ZipFile(args.output,'w') as dst:
        for info in src.infolist():
            data=src.read(info.filename)
            if info.filename=='AndroidManifest.xml':data=repair(data,args.authority)
            dst.writestr(info,data)
    with zipfile.ZipFile(args.output) as dst:assert dst.testzip() is None
    print('Updated only InitializationProvider authority; align and sign this APK before installing.')

if __name__=='__main__':main()
