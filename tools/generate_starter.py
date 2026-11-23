from __future__ import annotations
import json,random,itertools,collections
from pathlib import Path
r=random.Random(628145)

def permutations(n):
    return [p for p in itertools.permutations(range(n)) if all(abs(p[i]-p[i-1])>1 for i in range(1,n))]

def areas(n,queens,caps):
    board=[-1]*(n*n); size=[1]*n
    for row,col in enumerate(queens):board[row*n+col]=row
    todo=set(range(n*n))-{row*n+col for row,col in enumerate(queens)}
    while todo:
        edges=[]
        for i in todo:
            row,col=divmod(i,n)
            near=[]
            for y,x in [(row-1,col),(row+1,col),(row,col-1),(row,col+1)]:
                if not (0<=x<n and 0<=y<n):continue
                region=board[y*n+x]
                if region>=0 and size[region]<caps.get(region,n*n):near.append(region)
            if near:edges.append((i,near))
        if not edges:return None
        i,near=r.choice(edges)
        region=r.choice(near)
        board[i]=region;size[region]+=1;todo.remove(i)
    return board

def valid_solutions(n,board,perms,limit=2):
    sol=[]
    for p in perms:
        mask=0
        for y,x in enumerate(p):
            reg=board[y*n+x]
            if mask & (1<<reg):break
            mask |=1<<reg
        else:
            sol.append(p)
            if len(sol)>=limit:break
    return sol

def logical(n,regions):
    cand=[True]*(n*n);forced=set();passes=0;adjacency_removals=0
    while passes<100:
        passes+=1;change=False
        for pos in tuple(forced):
            y,x=divmod(pos,n)
            for i in range(n*n):
                yy,xx=divmod(i,n)
                if i!=pos and (yy==y or xx==x or regions[i]==regions[pos] or (abs(yy-y)<=1 and abs(xx-x)<=1)) and cand[i]:
                    cand[i]=False;change=True
        for groups in ([list(range(y*n,(y+1)*n)) for y in range(n)],[[y*n+x for y in range(n)] for x in range(n)],[[i for i,v in enumerate(regions) if v==reg] for reg in range(n)]):
            for group in groups:
                options=[i for i in group if cand[i]]
                if not options:return (False,passes,adjacency_removals)
                if len(options)==1 and options[0] not in forced:
                    forced.add(options[0]);change=True
        for i in range(n*n):
            if not cand[i]:continue
            y,x=divmod(i,n)
            for yy in (y-1,y+1):
                if 0<=yy<n and not any(cand[yy*n+xx] and abs(xx-x)>1 for xx in range(n)):
                    cand[i]=False;change=True;adjacency_removals+=1;break
        if len(forced)==n:
            if all(cand[i] for i in forced):return True,passes,adjacency_removals
            return False,passes,adjacency_removals
        if not change:return False,passes,adjacency_removals
    return False,passes,adjacency_removals

entries={}
for mode,n,caps in [('easy',6,[1,2]),('medium',7,[1,2]),('hard',8,[1,1])]:
    perms=permutations(n)
    chosen=[];seen=set();tries=0
    while len(chosen)<8 and tries<150000:
        tries+=1
        p=r.choice(perms)
        freeze=r.sample(range(n),len(caps))
        reg=areas(n,p,dict(zip(freeze,caps)))
        if reg is None or tuple(reg) in seen:continue
        if len(valid_solutions(n,reg,perms))!=1:continue
        ok,passes,support=logical(n,reg)
        if not ok or (mode=="hard" and passes<5):continue
        seen.add(tuple(reg));chosen.append({'size':n,'regions':reg})
    entries[mode]=chosen
    print(mode, 'available:',len(chosen),'tries:',tries, 'sample:',[logical(n,x['regions'])[1:] for x in chosen[:3]],flush=True)
    assert len(chosen)==8
out=Path(__file__).resolve().parent.parent/'data/starter_puzzles.json'
out.write_text(json.dumps({'version':1,'puzzles':entries},ensure_ascii=False,indent=2)+'\n')
print('seed data',out.stat().st_size)
