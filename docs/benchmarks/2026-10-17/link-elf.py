"""Minimal checked static linker for this single freestanding AArch64 object.
Only the explicit relocation kinds used by our object are accepted. No runtime
loader or shared library is used. All writable state is on stack or mmap.
"""
import pathlib, struct, sys
p=pathlib.Path(sys.argv[1]).read_bytes()
assert p[:6]==b'\x7fELF\x02\x01'
h=struct.unpack_from('<16sHHIQQQIHHHHHH',p)
assert h[1:3]==(1,183)
shoff,shsize,shnum=h[6],h[11],h[12]
sections=[struct.unpack_from('<IIQQQQIIQQ',p,shoff+i*shsize) for i in range(shnum)]
base=0x400000; body=bytearray(4096); offsets={}
for i,s in enumerate(sections):
 if s[2]&2:
  assert not (s[2]&1), 'Unexpected writable global section'
  align=max(s[8],1);body.extend(b'\0'*((-len(body))%align));offsets[i]=len(body)
  assert s[1]!=8 or s[5]==0,'Unexpected BSS'
  body.extend(p[s[4]:s[4]+s[5]])
def cstr(tab,n):return tab[n:tab.index(0,n)].decode()
symtabs={};entry=None
for i,s in enumerate(sections):
 if s[1]==2:
  strings=sections[s[6]];tab=p[strings[4]:strings[4]+strings[5]];syms=[]
  for off in range(s[4],s[4]+s[5],s[9]):
   name,info,other,index,value,size=struct.unpack_from('<IBBHQQ',p,off)
   address=base+offsets[index]+value if index in offsets else None
   syms.append((cstr(tab,name),address))
   if syms[-1][0]=='_start':entry=address
  symtabs[i]=syms
used=set()
for s in sections:
 if s[1]!=4 or s[7] not in offsets:continue
 for off in range(s[4],s[4]+s[5],s[9]):
  at,info,addend=struct.unpack_from('<QQq',p,off);kind=info&0xffffffff;symbol=info>>32
  name,S=symtabs[s[6]][symbol];assert S is not None,(name,kind)
  target=S+addend;loc=offsets[s[7]]+at;P=base+loc
  word=struct.unpack_from('<I',body,loc)[0];used.add(kind)
  if kind==257:struct.pack_into('<Q',body,loc,target);continue
  if kind in (282,283):
   d=target-P;assert d%4==0 and -(1<<27)<=d<(1<<27)
   word=(word&0xfc000000)|((d>>2)&0x3ffffff)
  elif kind==275:
   d=(target>>12)-(P>>12);assert -(1<<20)<=d<(1<<20)
   word=(word&~((3<<29)|(0x7ffff<<5)))|((d&3)<<29)|(((d>>2)&0x7ffff)<<5)
  elif kind==277:word=(word&~(0xfff<<10))|((target&0xfff)<<10)
  elif kind in (278,284,285,286,299):
   scale={278:0,284:1,285:2,286:3,299:4}[kind];assert target%(1<<scale)==0
   word=(word&~(0xfff<<10))|(((target&0xfff)>>scale)<<10)
  else:raise ValueError(('Unsupported relocation',kind,name))
  struct.pack_into('<I',body,loc,word)
assert entry and base+4096<=entry<base+len(body)
eh=struct.pack('<16sHHIQQQIHHHHHH',b'\x7fELF\x02\x01\x01'+b'\0'*9,2,183,1,entry,64,0,0,64,56,2,0,0,0)
ph=struct.pack('<IIQQQQQQ',1,5,0,base,base,len(body),len(body),65536)
stack=struct.pack('<IIQQQQQQ',0x6474e551,6,0,0,0,0,0,16)
body[:64]=eh;body[64:120]=ph;body[120:176]=stack
out=pathlib.Path(sys.argv[2]);out.write_bytes(body);out.chmod(0o755)
print('Built checked static AArch64 ELF:',len(body),'bytes; relocations:',sorted(used))
