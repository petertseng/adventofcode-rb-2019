m=$*.shift.split(?,).map &:to_i;
b=z=0;
while(c=m[z])!=99;
  y=-2;
  a,(r,q)=m[z+1,3].map{|x|
    d=c.to_s[y-=1];
    x||=0;
    [
      x+=d==?2?b:0,
      d==?1?x:m[x]||0
    ]
  }.transpose;
  # Since 0 is not a valid opcode,
  # index from the back instead of the front,
  # saving one array entry (2 bytes) but costing one - (1 byte).
  s=%i[== < == != x x * +][-c%=100];
  n,j=
    c==3?(m[a[0]]=gets.to_i;2):
    c==4?(p r;2):
    c==5||c==6?[3,r.send(s,0)&&q]:
    c==9?(b+=r;2):
    (x=r.send s,q;m[a[2]]=c<3?x:x ?1:0;4);
  z=j||z+n;
end
