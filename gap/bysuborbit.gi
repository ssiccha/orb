#############################################################################
##
##  byorbits.gi              orb package                      
##                                                           Max Neunhoeffer
##                                                              Felix Noeske
##
##  Copyright 2005 Lehrstuhl D für Mathematik, RWTH Aachen
##
##  Implementation stuff for fast orbit enumeration by suborbits.
##
#############################################################################

###########################
# A few helper functions: #
###########################

InstallGlobalFunction( ORB_PrettyStringBigNumber,
function(n)
  local e,i,s;
  if n < 0 then
    e := "-";
    n := -n;
  else
    e := "";
  fi;
  s := String(n);
  i := 1;
  while i < Length(s) do
    Add(e,s[i]);
    if (Length(s)-i) mod 3 = 0 then
      Add(e,' ');
    fi;
    i := i + 1;
  od;
  Add(e,s[i]);
  return e;
end );

InstallGlobalFunction( ORB_InvWord, 
function(w)
  local wi,l,i;
  # Inverts w by changing the sign and reversing
  wi := ShallowCopy(w);
  l := Length(w);
  for i in [1..l] do
    wi[l+1-i] := - w[i];
  od;
  return wi;
end );

InstallGlobalFunction( ORB_ApplyWord, 
function(p,w,l,li,op)
  # p is a point, w is a word given as a list of small integers which are
  # indices in the list l or negatives of indices in the list li,
  # which is a list of group elements g, for which
  # op(p,g) is defined. 
  # Example: ORB_ApplyWord(p,[1,-2,3,2],[g1,g2,g3],[g1^-1,g2^-1,g3^-1],OnRight) 
  #          = p*g1*(g2^-1)*g3*g2
  local i;
  for i in w do
    if i < 0 then
      p := op(p,li[-i]);
    else
      p := op(p,l[i]);
    fi;
  od;
  return p;
end );

#########################
# Stabilizer Iterators: #
#########################

InstallMethod( StabIterator, "without arguments", [],  
  function( )
    local stab;
    stab := rec();
    Objectify( StdStabIteratorsType, stab );
    return stab;
  end );

InstallMethod( ViewObj, "for a stab iterator", 
  [ IsStabIterator and IsStdStabIteratorRep ],
  function( stab )
    if not(IsBound(stab!.i)) then
        Print("<newly born stab iterator>");
    else
        Print("<stabiterator size=",stab!.info," position=",stab!.pos,">");
    fi;
  end );

InstallMethod( Reset, "for a stab iterator",
  [ IsStabIterator and IsStdStabIteratorRep ],
function(stab)
  if not(IsBound(stab!.i)) then
      Error("StabIterator is not yet initialized");
      return;
  fi;
  stab!.pos := List(stab!.info,x->1);
  stab!.point := List([1..stab!.i],x->[]);
  stab!.cache := List([1..stab!.i],x->[]);
end );

InstallOtherMethod( Size, "for a std stab iterator",
  [ IsStabIterator and IsStdStabIteratorRep ],
  function( stab )
    return Product( stab!.info, Length );
  end );

InstallMethod( Next, "for a stab iterator",
  [ IsStabIterator and IsStdStabIteratorRep ],
function(stab)
  local i;
  i := 1;
  while true do
    if i > Length(stab!.pos) then
      return true;   # finished with this iterator
    fi;
    stab!.pos[i] := stab!.pos[i]+1;
    stab!.point[i] := [];    # this is no longer valid
    if stab!.pos[i] <= Length(stab!.info[i]) then
      return false;  # next element found
    fi;
    stab!.pos[i] := 1;
    i := i + 1;
  od;
  # this is never reached
end );

InstallGlobalFunction( ORB_ApplyStabElement,
function(p,j,i,setup,stab,w)
  local ww,www;
  while true do
    if i > 1 and IsBound(stab!.point[i][j]) and p = stab!.point[i][j] then
      if IsList(w) then Append(w,stab!.cache[i][j][1]); fi;
      p := stab!.cache[i][j][2];
    else
      stab!.point[i][j] := p;

      ww := ShallowCopy(setup!.trans[i][stab!.info[i][stab!.pos[i]]]);
      if IsList(w) then Append(w,ww); fi;
      p := ORB_ApplyWord(p,ww,setup!.els[j],setup!.elsinv[j],setup!.op[j]);
      if i = 1 then
        return p;
      fi;
      www := [];
      p := ORB_Minimalize(p,j,i,setup,false,www);
      Append(ww,www);
      if IsList(w) then Append(w,www); fi;

      stab!.cache[i][j] := [ww,p];
    fi;
    i := i - 1;
  od;
  # never comes here
end );


############################################
# The heart of the method: Minimalization: #
############################################

InstallMethod( ViewObj, "for an orbit-by-suborbit setup object",
  [ IsOrbitBySuborbitSetup and IsStdOrbitBySuborbitSetupRep ],
  function( setup )
    Print("<setup for an orbit-by-suborbit enumeration, k=",setup!.k,">");
  end );

InstallMethod( Memory, "for an orbit-by-suborbit setup object",
  [ IsOrbitBySuborbitSetup and IsStdOrbitBySuborbitSetupRep ],
  function( setup )
    local k,m,p,i;
    k := setup!.k;
    m := 0;
    for i in [1..k] do
        p := SHALLOW_SIZE(setup!.sample[i]) + 3 * GAPInfo.BytesPerVariable;
        m := m + p * setup!.info[i].nr + 2 * SHALLOW_SIZE(setup!.info[i].els);
    od;
    return m;
  end );

InstallGlobalFunction( ORB_Minimalize,
function(p,j,i,setup,stab,w)
  # p is a point that should be minimalized. j is in 1..k+1 and indicates,
  # whether p is in P_j or in P (for j=k+1). i is in 1..k and indicates, 
  # which group U_i is used to minimalize. So only i <= j makes sense.
  # setup is a record describing the helper subgroups as defined above. 
  # Returns a U_i-minimal point q in the same U_i-orbit pU_i.
  # If stab is "false" nothing happens. If stab is a stabiterator object,
  # (usually will be "newly born" thus empty), that will
  # be filled with information for an iterator object for 
  # Stab_{U_i}(pi[j][i](q)) (see above).
  # If w is a list the word which is applied is appended.
  local m,minpoint,minstab,minstablen,minword,n,q,qq,qqq,ret,stablen,
        tempstab,v,vv,vvv,ww,www;
#Print("Mini:",j," ",i,"\n");
  if i = 1 then    # this is the smallest helper subgroup

    # go to P_1:
    if j > i then 
      q := setup!.pifunc[j][i](p,setup!.pi[j][i]); 
    else
      q := p;
    fi;
    v := ValueHT(setup!.info[i],q);
    if v = fail then    # we do not yet know this point
      ###Print("<\c");
      # we have to enumerate this U_1-orbit, apply all elements in trans:
      v := [];  # here we collect the stabilizer
      for m in [1..setup!.index[i]] do
        qq := ORB_ApplyWord(q,ORB_InvWord(setup!.trans[i][m]),
                        setup!.els[i],setup!.elsinv[i],setup!.op[i]);
        if q = qq then   # we found a stabilizer element:
          Add(v,m);
        else
          vv := ValueHT(setup!.info[i],qq);
          if vv = fail then    # we did not yet reach this point
            AddHT(setup!.info[i],qq,m);   # store this info
          fi;
        fi;
      od;
      AddHT(setup!.info[i],q,v);
      setup!.suborbnr[i] := setup!.suborbnr[i] + 1;
      setup!.sumstabl[i] := setup!.sumstabl[i] + Length(v);
      ###Print(Length(v),":",QuoInt(setup!.sumstabl[i],
      ###      setup!.suborbnr[i]),">   \r");

      # now p is by definition U_1-minimal
    else    # we already know this U_1-orbit:
      if IsInt(v) then   # this is the number of a word
        if IsList(w) then Append(w,setup!.trans[i][v]); fi;  # store what we do
        p := ORB_ApplyWord(p,setup!.trans[i][v],setup!.els[j],
                           setup!.elsinv[j],setup!.op[j]);
        if j > i then
          q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
        else
          q := p;
        fi;
        v := ValueHT(setup!.info[i],q);
      fi; # otherwise we are already U_1-minimal:
    fi;
    if IsStabIterator(stab) then
        stab!.i := 1;
        stab!.info := [v];
        stab!.pos := [1];
    fi;
#Print("Raus\n");
    return p;

  else   # we are in some higher helper subgroup than U_1:

    # first do a U_{i-1}-minimalization:
    p := ORB_Minimalize(p,j,i-1,setup,stab,w);

    # now try to reach the minimal U_{i-1}-suborbit in the U_i-orbit:
    if j > i then
      q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
    else
      q := p;
    fi;
    v := ValueHT(setup!.info[i],q);

    if v = fail then    # we do not yet know this U_{i-1}-suborbit

      ###Print("<",i,":\c");
      # first we apply all elements of the transversal of U_{i-1} in U_i,
      # U_{i-1}-minimalize them and search for the smallest stabilizer
      # to choose the U_i-minimal U_{i-1}-orbit:
      minpoint := fail;
      minword := fail;
      minstablen := -1;
      minstab := fail;
      for m in [1..setup!.index[i]] do
        tempstab := StabIterator();
        qq := ORB_ApplyWord(q,setup!.trans[i][m],setup!.els[i],
                            setup!.elsinv[i],setup!.op[i]);
        ww := ShallowCopy(setup!.trans[i][m]);
        qq := ORB_Minimalize(qq,i,i-1,setup,tempstab,ww);
        stablen := Product(tempstab!.info,Length);
        if minpoint = fail or stablen < minstablen then
          minpoint := qq;
          minstablen := stablen;
          minword := ww;
          minstab := tempstab;
        fi;
      od;
      # Now U_i-minimalize p:
      p := ORB_ApplyWord(p,minword,setup!.els[j],setup!.elsinv[j],setup!.op[j]);
      if IsList(w) then Append(w,minword); fi;
      q := minpoint;
      # in the second component we have to collect stabilizing transversal 
      # elements for subgroups U_1 to U_i:
      v := [true,List([1..i],x->[])];  
      AddHT(setup!.info[i],q,v);
                        
      # Now the U_{i-1}-orbit of the vector q is the U_i-minimal 
      # U_{i-1}-orbit and q is the U_i-minimal vector
      
      # first find all U_{i-1}-minimal elements in the U_i-minimal 
      # U_{i-1}-orbit:
      Reset(minstab);
      repeat
        ww := [];
        qq := ORB_ApplyStabElement(q,i,i-1,setup,minstab,ww);
        if qq <> q then   # some new U_{i-1}-minimal element?
          vv := ValueHT(setup!.info[i],qq);
          if vv = fail then
            AddHT(setup!.info[i],qq,[false,ORB_InvWord(ww)]);
          fi;
        else   # in this case this is an element of Stab_{U_{i-1}}(q) in P_i
          for n in [1..i-1] do
            AddSet(v[2][n],minstab!.info[n][minstab!.pos[n]]);
          od;
        fi;
      until Next(minstab);
      
      # we have to enumerate this U_i-orbit by U_{i-1}-orbits, storing
      # information for all U_{i-1}-minimal vectors:
      tempstab := StabIterator();
      for m in [1..setup!.index[i]] do
        # Apply t to find other U_{i-1}-orbits
        qq := ORB_ApplyWord(q,setup!.trans[i][m],setup!.els[i],
                            setup!.elsinv[i],setup!.op[i]);
        ww := ShallowCopy(setup!.trans[i][m]);
        qq := ORB_Minimalize(qq,i,i-1,setup,tempstab,ww);
        vv := ValueHT(setup!.info[i],qq);
        if vv <> fail and not(IsInt(vv)) then  
          # we are again in the U_i-minimal U_{i-1}-o.
          # then m has to go in the stabilizer info:
          Add(v[2][i],m);
        fi;
        if vv = fail then   # a new U_{i-1}-orbit
          # note that we now have stabilizer info in tempstab
          ret := setup!.cosetrecog[i](i,ORB_InvWord(ww),setup);
          AddHT(setup!.info[i],qq,ret);
          Reset(tempstab);
          repeat
            www := ShallowCopy(ww);
            qqq := ORB_ApplyStabElement(qq,i,i-1,setup,tempstab,www);
            vvv := ValueHT(setup!.info[i],qqq);
            if vvv = fail then
              ret := setup!.cosetrecog[i](i,ORB_InvWord(www),setup);
              AddHT(setup!.info[i],qqq,ret);
            fi;
          until Next(tempstab);
        fi;
      od;
      # now q is by definition the U_i-minimal point in the orbit and
      # v its setup!.info[i], i.e. [true,stabilizer information]
      setup!.suborbnr[i] := setup!.suborbnr[i] + 1;
      setup!.sumstabl[i] := setup!.sumstabl[i] + Product(v[2],Length);
      ###Print(Product(v[2],Length),":",
      ###      QuoInt(setup!.sumstabl[i],setup!.suborbnr[i]),">      \r");

    else   # we already knew this U_{i-1}-suborbit

      if IsInt(v) then    # this is the number of a word
        if IsList(w) then 
          Append(w,setup!.trans[i][v]);   # remember what we did
        fi;
        p := ORB_ApplyWord(p,setup!.trans[i][v],setup!.els[j],
                           setup!.elsinv[j],setup!.op[j]);
        # we again do a U_{i-1}-minimalization:
        p := ORB_Minimalize(p,j,i-1,setup,stab,w);
        # now we are in the U_i-minimal U_{i-1}-suborbit and on a 
        # U_{i-1}-minimal element
        if j > i then
          q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
        else
          q := p;
        fi;
        v := ValueHT(setup!.info[i],q);
      fi;
      if v[1] = false then    # not yet U_i-minimal 
        # we still have to apply an element of Stab_{U_{i-1}}(pi[j][i-1](p)):
        if IsList(w) then Append(w,v[2]); fi;  # remember what we did
        p := ORB_ApplyWord(p,v[2],setup!.els[j],setup!.elsinv[j],setup!.op[j]);
        if j > i then
          q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
        else
          q := p;
        fi;
        v := ValueHT(setup!.info[i],q);
      fi;
      # now q is the U_i-minimal element in qU_i
      # v is now [true,stabilizer information]

    fi;

    if IsStabIterator(stab) then
        stab!.i := i;
        stab!.info := v[2];
        stab!.pos := List([1..i],x->1);
    fi;

    # now we are on the minimal element in the S-orbit
#Print("raus\n");
    return p;
  fi;
end );


#######################
# Suborbit databases: #
#######################

InstallMethod( SuborbitDatabase, "for an orbit by suborbit setup object",
  [ IsOrbitBySuborbitSetup, IsPosInt ],
  function( setup, hashlen )
    local r;
    r := rec( reps := [], lengths := [], setup := setup, totallength := 0 );
    r.mins := NewHT( setup!.sample[setup!.k+1], hashlen );
    Objectify( StdSuborbitDatabasesType, r );
    return r;
  end );

InstallMethod( ViewObj, "for a suborbit database",
  [ IsSuborbitDatabase and IsStdSuborbitDbRep ],
  function( db )
    Print( "<suborbit database with ",Length(db!.reps)," suborbits, total ",
           "size: ", Sum(db!.lengths), ">" );
  end );

InstallMethod( StoreSuborbit, 
  "for a suborbit database, a point, a stabiterator, and a setup object",
  [ IsSuborbitDatabase and IsStdSuborbitDbRep, IsObject, IsStabIterator ],
  function(db,p,stab)
  # "db" must be a suborbit database
  # "p" must be a U-minimal element, which is not yet known
  # "stab" must be stabilizer information coming from minimalization
  # all U-minimal elements in the same orbit are calculated and stored
  # in the hash, in addition "p" is appended as representative to
  # "suborbits" and the orbit length is calculated and appended to
  # "lengths".
  local setup, k, firstgen, lastgen, li, i, j, pp, vv, nrmins, length,stabsize;
        
  setup := db!.setup;
  k := setup!.k;
  Add(db!.reps,p);
  AddHT(db!.mins,p,Length(db!.reps));
  ###Print("[",Product(stab.info,Length),"\c");
  if Size(stab) = setup!.size[k] then
    # better use a standard orbit algorithm:
    if k = 1 then
      firstgen := 1;
    else
      firstgen := Length(setup!.els[k-1])+1;
    fi;
    lastgen := Length(setup!.els[k]);
    li := [p];
    i := 1;
    while i <= Length(li) do
      for j in [firstgen..lastgen] do
        pp := setup!.op[k+1](li[i],setup!.els[k+1][j]);  # ???
        vv := ValueHT(db!.mins,pp);
        if vv = fail then
          AddHT(db!.mins,pp,Length(db!.reps));
          Add(li,pp);
        fi;
      od;
      i := i + 1;
    od;
    nrmins := Length(li);
    length := nrmins;
  else
    Reset(stab);
    nrmins := 1;
    stabsize := 0;
    repeat
      pp := ORB_ApplyStabElement(p,k+1,k,setup,stab,false);
      if p = pp then  # we got a real stabilizer element of p
        stabsize := stabsize + 1;
      else  # we could have stepped to some other U-minimal element
        vv := ValueHT(db!.mins,pp);
        if vv = fail then
          AddHT(db!.mins,pp,Length(db!.reps));
          nrmins := nrmins+1;
        fi;
      fi;
    until Next(stab);
    length := setup!.size[k] / stabsize;
  fi;
  Add(db!.lengths,length);
  db!.totallength := db!.totallength + length;
  ###Print("]\r");
  Print("\rNew #",Length(db!.reps),
        ", size ",ORB_PrettyStringBigNumber(length),", ");
  Print("NrMins: ",nrmins,", ");
  return length;
end );

InstallMethod( LookupSuborbit, 
  "for a (minimal) point and a std suborbit database",
  [ IsObject, IsSuborbitDatabase and IsStdSuborbitDbRep ],
  function( p, db )
    return ValueHT( db!.mins, p );
  end );

InstallMethod( TotalLength, "for a std suborbit database",
  [ IsSuborbitDatabase and IsStdSuborbitDbRep ],
  function( db )
    return db!.totallength;
  end );

InstallMethod( Representatives, "for a std suborbit database",
  [ IsSuborbitDatabase and IsStdSuborbitDbRep ],
  function( db )
    return db!.reps;
  end );

InstallMethod( Memory, "for a std suborbit database",
  [ IsSuborbitDatabase and IsStdSuborbitDbRep ],
  function( db )
    local m,p;
    # The lists:
    m := 2 * SHALLOW_SIZE(db!.reps) + 2 * SHALLOW_SIZE(db!.mins!.els);
    #  (db!.reps and db!.lengths   and    els and vals in db!.mins)
    # Now the points (this assumes vectors!):
    p := SHALLOW_SIZE(db!.setup!.sample[db!.setup!.k+1])
         + 3 * GAPInfo.BytesPerVariable;   # for the bag
    m := m + db!.mins!.nr * p;  # the reps are also in mins!
    return m;
  end );


###################################
# The real thing: OrbitBySuborbit #
###################################

# First a few methods for IsOrbitBySuborbit objects:

InstallMethod( ViewObj, "for an orbit-by-suborbit",
  [ IsOrbitBySuborbit and IsStdOrbitBySuborbitRep ],
  function( o )
    Print( "<orbit-by-suborbit size=",o!.orbitlength," stabsize=",
           o!.stabsize );
    if o!.percentage < 100 then
        Print(" (",o!.percentage,"%)");
    fi;
    if o!.db!.mins!.nr <> 0 then
        Print(" saving factor=", QuoInt(o!.db!.totallength,o!.db!.mins!.nr));
    fi;
    Print(">");
  end );

InstallOtherMethod( Size, "for an orbit-by-suborbit",
  [ IsOrbitBySuborbit and IsStdOrbitBySuborbitRep ],
  function( o )
    return o!.orbitlength;
  end );

InstallOtherMethod( StabilizerOfExternalSet, "for an orbit-by-suborbit",
  [ IsOrbitBySuborbit and IsStdOrbitBySuborbitRep ],
  function( o )
    return o!.stab;
  end );

InstallMethod( SuborbitsDb, "for an orbit-by-suborbit",
  [ IsOrbitBySuborbit and IsStdOrbitBySuborbitRep ],
  function( o )
    return o!.db;
  end );

InstallMethod( WordsToSuborbits, "for an orbit-by-suborbit",
  [ IsOrbitBySuborbit and IsStdOrbitBySuborbitRep ],
  function( o )
    return o!.words;
  end );
  
InstallMethod( Memory, "for an orbit-by-suborbit",
  [ IsOrbitBySuborbit and IsStdOrbitBySuborbitRep ],
  function( o )
    local m1,m2;
    m1 := Memory(o!.db);
    m2 := Memory(o!.db!.setup);
    Info(InfoOrb,1,"Memory for suborbits database : ",
         ORB_PrettyStringBigNumber(m1));
    Info(InfoOrb,1,"Memory for setup (factor maps): ",
         ORB_PrettyStringBigNumber(m2));
    return [m1,m2];
  end );

InstallGlobalFunction( OrbitBySuborbit,
function(p,hashlen,size,setup,percentage)
  # Enumerates the orbit of p under the group G generated by "gens" by
  # suborbits for the subgroup U described in "setup". 
  # "p" is a point
  # "hashlen" is an upper bound for the set of U-minimal points in the G-orbit
  # "size" is the group order to stop when we are ready and as upper bound
  #        for the orbit length
  # "setup" is a setup object for the iterated quotient trick,
  #         effectively enabling us to do minimalization with a subgroup
  # "percentage" is a number between 50 and 100 and gives a stopping criterium.
  #         We stop if percentage of the orbit is enumerated.
  #         Only over 50% we know that the stabilizer is correct!
  # Returns a suborbit database with additional field "words" which is
  # a list of words in gens which can be used to reach U-orbit in the G-orbit

  local k,firstgen,lastgen,stab,miniwords,db,stabgens,stabperms,stabilizer,
        fullstabsize,words,todo,i,j,x,mw,done,newperm,newword,oldtodo,sw,xx,v,
        pleaseexitnow,assumestabcomplete;

  pleaseexitnow := false;  # set this to true in a break loop to
                           # let this function exit gracefully
  assumestabcomplete := false;  # set this to true in a break loop to
                                # let this function assume that the 
                                # stabilizer is complete

  # Setup some shortcuts:
  k := setup!.k;
  firstgen := Length(setup!.els[k])+1;
  lastgen := Length(setup!.els[k+1]);

  # A security check:
  if p <> setup!.op[k+1](p,setup!.els[k+1][1]^0) then
      Error("Warning: The identity does not preserve the starting point!\n",
            "Did you normalize your vector?");
  fi;

  # First we U-minimalize p:
  stab := StabIterator();
  p := ORB_Minimalize(p,k+1,k,setup,stab,false);

  miniwords := [[]];  # here we collect U-minimalizing elements
  
  # Start a database with the first U-suborbit:
  db := SuborbitDatabase(setup,hashlen);
  StoreSuborbit(db,p,stab);

  stabgens := [];
  stabperms := [];
  stabilizer := Group(setup!.permgens[1]^0);
  if IsBound( setup!.stabchainrandom ) then
      StabChain( stabilizer, rec( random := setup!.stabchainrandom ) );
  else
      StabChain(stabilizer);
  fi;
  fullstabsize := 1;
  
  words := [[]];
  todo := [[]];
  while true do

    i := 1;
    while i <= Length(todo) do
      if pleaseexitnow = true then return "didnotfinish"; fi;

      for j in [firstgen..lastgen] do
        x := setup!.op[k+1](p,setup!.els[k+1][j]);   # ???
        x := ORB_ApplyWord(x,todo[i],setup!.els[k+1],
                           setup!.elsinv[k+1],setup!.op[k+1]);   # ???
        mw := [];
        x := ORB_Minimalize(x,k+1,k,setup,stab,mw);
        v := LookupSuborbit(x,db);
        if v = fail then
          Add(words,Concatenation([j],todo[i]));
          Add(todo,Concatenation([j],todo[i]));
          Add(miniwords,mw);
          StoreSuborbit(db,x,stab);
          Print("total: ",ORB_PrettyStringBigNumber(TotalLength(db)),
                " stab: ",ORB_PrettyStringBigNumber(fullstabsize),"       \r");
          if 2 * TotalLength(db) * fullstabsize > size and
             TotalLength(db) * fullstabsize >= QuoInt(size*percentage,100) then 
            Print("\nDone!\n");
            return Objectify( StdOrbitBySuborbitsType,
                       rec(db := db,
                       words := words,
                       stabsize := fullstabsize,
                       stab := stabilizer,
                       groupsize := size,
                       orbitlength := size/fullstabsize,
                       percentage := percentage) );
          fi;
        else
          if assumestabcomplete = false and
             TotalLength(db) * fullstabsize * 2 <= size then
            # otherwise we know that we will not find more stabilizing els.
            # we know now that v is an integer and that
            # p*setup!.els[j]*todo[i]*U = p*words[v]*U
            # p*setup!.els[j]*todo[i]*mw is our new vector
            # p*words[v]*miniwords[v] is our old vector
            # they differ by an element in Stab_U(...)
            Reset(stab);
            done := false;
            repeat
              sw := [];
              xx := ORB_ApplyStabElement(x,k+1,k,setup,stab,sw);
              if xx = Representatives(db)[v] then  
                # we got a real stabilizer element of p
                done := true;
                newword := Concatenation([j],todo[i],mw,sw,
                            ORB_InvWord(miniwords[v]),ORB_InvWord(words[v]));
                newperm := ORB_ApplyWord(setup!.permgens[1]^0,newword,
                                 setup!.permgens,setup!.permgensinv,OnRight);
                if not(IsOne(newperm)) then
                  if not(newperm in stabilizer) then
                    Add(stabgens,newword);
                    Add(stabperms,newperm);
                    stabilizer := GroupWithGenerators(stabperms);
                    Print("\nCalculating new estimate of the stabilizer...\c");
                    if IsBound(setup!.stabchainrandom) then
                        StabChain(stabilizer, 
                                  rec(random := setup!.stabchainrandom));
                    else
                        StabChain(stabilizer);
                    fi;
                    fullstabsize := Size(stabilizer);
                    Print("done.\nNew stabilizer order: ",fullstabsize,"\n");
                    if TotalLength(db) * fullstabsize 
                       >= QuoInt(size*percentage,100) then 
                      Print("Done!\n");
                      return Objectify( StdOrbitBySuborbitsType,
                             rec(db := db,
                                 words := words,
                                 stabsize := fullstabsize,
                                 stab := stabilizer,
                                 groupsize := size,
                                 orbitlength := size/fullstabsize,
                                 percentage := percentage) );
                    fi;
                  fi;
                fi;
              fi;
            until done or Next(stab);
          fi;
        fi;
      od;
      i := i + 1;
    od;
  
    oldtodo := todo;
    todo := [];
    for i in [1..Length(stabgens)] do
      Append(todo,List(oldtodo,w->Concatenation(stabgens[i],w)));
    od;
    Print("\nLength of next todo: ",Length(todo),"\n");
  od;
  # this is never reached
end );

InstallMethod( Next, "for a stab iterator and a string",
  [ IsStabIterator and IsStdStabIteratorRep, IsString ],
function(stab,st)
  local i;
  i := stab!.i;
  while true do
    if i < 1 then
      return true;   # finished with this iterator
    fi;
    stab!.pos[i] := stab!.pos[i]+1;
    stab!.point[i] := [];
    if stab!.pos[i] <= Length(stab!.info[i]) then
      return false;  # next element found
    fi;
    stab!.pos[i] := 1;
    i := i - 1;
  od;
  # this is never reached
end );

InstallGlobalFunction( ORB_ApplyUElement,
function(p,j,i,setup,stab,w)
  local ww;
  while i >= 1 do
    ww := ShallowCopy(setup!.trans[i][stab!.info[i][stab!.pos[i]]]);
    if IsList(w) then Append(w,ww); fi;
    p := ORB_ApplyWord(p,ww,setup!.els[j],setup!.elsinv[j],setup!.op[j]);
    i := i - 1;
  od;
  return p;
end );

InstallGlobalFunction( OrbitBySuborbitWithKnownSize,
function(p,hashlen,size,setup,randels)
  # Enumerates the orbit of p under the group G generated by "gens" by
  # suborbits for the subgroup U described in "setup". 
  #   "p" is a point
  #   "hashlen" is an upper bound for the set of U-minimal points in the G-orbit
  #   "size" is the orbit length
  #   "setup" is a record of data for the iterated quotient trick,
  #           effectively enabling us to do minimalization with a subgroup
  #   "randels" number of random elements to use for recognising half orbits
  # Returns a record with components:
  #   "db": suborbit database
  #   "words": a list of words in gens which can be used to reach 
  #            U-orbit in the G-orbit
  local k,stab,q,trans,db,l,i,Ucounter,g,j,x,y,v,ii,w,z,firstgen,lastgen;

  k := setup!.k;
  firstgen := Length(setup!.els[k])+1;
  lastgen := Length(setup!.els[k+1]);

  # First we U-minimalize p:
  stab := StabIterator();
  q := ORB_Minimalize(p,k+1,k,setup,stab,false);

  trans := [[]];    # words for getting to the U-suborbits
  
  # Start a database with the first U-suborbit:
  db := SuborbitDatabase(setup,hashlen);
  StoreSuborbit(db,q,stab);

  l := [p];
  i := 1;   # counts elements in l
  # use a stabilizer info, which describes all of U:
  Ucounter := StabIterator();
  Ucounter!.i := k;
  Ucounter!.info := List([1..k],i->[1..setup!.index[i]]);
  Ucounter!.pos := List([1..k],i->1);

  # Throw in some vectors gotten by applying random elements:
  g := GroupWithGenerators(setup!.els[k+1]{[firstgen..lastgen]});
  for j in [1..randels] do
      Print("Applying random element ",j," (",randels,") ...\n");
      x := p * PseudoRandom(g);
      y := ORB_Minimalize(x,k+1,k,setup,stab,false);
      v := LookupSuborbit(y,db);
      if v = fail then
          Add(l,x);
          Add(trans,[fail]);
          StoreSuborbit(db,y,stab);
          Print("total: ",ORB_PrettyStringBigNumber(TotalLength(db)),"     \n");
      fi;
      if TotalLength(db) >= size then 
        Print("\nDone.\n");
        return rec( db := db, words := trans ); 
      fi;
  od;
  Unbind(g);
   
  Reset(Ucounter);
  repeat
    while i <= Length(l) do
      for j in [firstgen..lastgen] do
        x := setup!.op[k+1](l[i],setup!.els[k+1][j]);
        y := ORB_Minimalize(x,k+1,k,setup,stab,false);
        v := LookupSuborbit(y,db);
        if v = fail then
          Add(trans,Concatenation(trans[i],[j]));
          Add(l,x);
          StoreSuborbit(db,y,stab);
          Print("total: ",ORB_PrettyStringBigNumber(TotalLength(db)),"     \r");
          if TotalLength(db) >= size then 
            Print("\nDone.\n");
            return rec( db := db, words := trans ); 
          fi;
        fi;
      od;
      i := i + 1;
    od;
    # now we have to to something else, perhaps applying some U elements?
    Print(".\c");
    for ii in [1..Length(l)] do
      w := [];
      z := ORB_ApplyUElement(l[ii],k+1,k,setup,Ucounter,w);
      for j in [firstgen..lastgen] do
        x := setup!.op[k+1](z,setup!.els[k+1][j]);
        y := ORB_Minimalize(x,k+1,k,setup,stab,false);
        v := LookupSuborbit(y,db);
        if v = fail then
          Add(trans,Concatenation(trans[ii],w,[j]));
          Add(l,x);
          StoreSuborbit(db,y,stab);
          Print("total: ",ORB_PrettyStringBigNumber(TotalLength(db)),"     \r");
          if TotalLength(db) >= size then 
            Print("\nDone.\n");
            return rec( db := db, words := trans ); 
          fi;
        fi;
      od;
    od;
  until Next(Ucounter,"fromabove");

  Print("Warning! Orbit not complete!!!\n");
  # this should never happen!
  return rec( db := db, words := trans );
end );


############################
# Convenient preparations: #
############################

InstallGlobalFunction( OrbitBySuborbitBootstrapForVectors,
function(gens,permgens,sizes,codims)
  # Returns a setup object for a list of helper subgroups
  # gens: a list of lists of generators for U_1 < U_2 < ... < U_k < G
  # permgens: the same in a faithful permutation representation
  # sizes: a list of sizes of groups U_1 < U_2 < ... < U_k
  # codims: a list of dimensions of factor modules
  # note that the basis must be changed to make projection easy!
  # That is, projection is taking the components [1..codim].

  local dim,doConversions,f,i,j,k,nrgens,nrgenssum,o,regvec,sample,setup,sum,v,
        counter,merk,neededfullspace;

  # For the old compressed matrices:
  if IsGF2MatrixRep(gens[1][1]) or Is8BitMatrixRep(gens[1][1]) then
      doConversions := true;
  else
      doConversions := false;
  fi;

  # Some preparations:
  k := Length(sizes);
  if Length(gens) <> k+1 or Length(permgens) <> k+1 or Length(codims) <> k then
      Error("Need generators for ",k+1," groups and ",k," codimensions.");
      return;
  fi;
  nrgens := List(gens,Length);
  nrgenssum := 0*nrgens;
  sum := 0;
  for i in [1..k+1] do
      nrgenssum[i] := sum;
      sum := sum + nrgens[i];
  od;
  nrgenssum[k+2] := sum;

  sample := gens[1][1][1];  # first vector of first generator

  # Do the first step:
  setup := rec(k := 1);
  setup.size := [sizes[1]];
  setup.index := [sizes[1]];
  setup.permgens := Concatenation(permgens);
  setup.permgensinv := List(setup.permgens,x->x^-1);
  setup.els := [];
  setup.els[k+1] := Concatenation(gens);
  setup.elsinv := [];
  setup.elsinv[k+1] := List(setup.els[k+1],x->x^-1);
  dim := Length(gens[1][1]);
  codims[k+1] := dim;   # for the sake of completeness!
  for j in [1..k] do
      setup.els[j] := List(Concatenation(gens{[1..j]}),
                           x->ExtractSubMatrix(x,[1..codims[j]],
                                                 [1..codims[j]]));
      if doConversions then
          for i in setup.els[j] do ConvertToMatrixRep(i); od;
      fi;
      setup.elsinv[j] := List(setup.els[j],x->x^-1);
  od;
  f := BaseField(gens[1][1]);
  regvec := ZeroVector(sample,codims[1]);  
            # a new empty vector over same field
  Info(InfoOrb,1,"Looking for regular U1-orbit in factor space...");
  counter := 0;
  repeat
      counter := counter + 1;
      Randomize(regvec);
      o := Enumerate(InitOrbit(setup.els[1],regvec,OnRight,sizes[1]*2,
                               rec(schreier := true)));
      Info(InfoOrb,2,"Found length: ",Length(o!.orbit));
  until Length(o!.orbit) = sizes[1] or counter >= 10;
  if Length(o!.orbit) < sizes[1] then   # Bad luck, try something else:
    regvec := ZeroMutable(sample);
    Info(InfoOrb,1,"Looking for regular U1-orbit in full space...");
    counter := 0;
    repeat
        counter := counter + 1;
        Randomize(regvec);
        o := Enumerate(InitOrbit(gens[1],regvec,OnRight,sizes[1]*2,
                                 rec(schreier := true)));
        Info(InfoOrb,2,"Found length: ",Length(o!.orbit));
    until Length(o!.orbit) = sizes[1] or counter >= 10;
    if Length(o!.orbit) < sizes[1] then   # Again bad luck, try the regular rep
        Info(InfoOrb,1,"Using the regular permutation representation...");
        o := Enumerate(InitOrbit(gens[1],gens[1]^0,OnRight,sizes[1]*2,
                                 rec(schreier := true)));
    fi;
  fi;
  Info(InfoOrb,2,"Found!");
  setup.trans := [List([1..Length(o!.orbit)],i->TraceSchreierTreeForward(o,i))];

  # Note that for k=1 we set codims[2] := dim
  setup.pi := [];
  setup.pifunc := [];
  for j in [2..k+1] do
      setup.pi[j] := [];
      setup.pifunc[j] := [];
      for i in [1..j-1] do
          setup.pi[j][i] := [1..codims[i]];
          setup.pifunc[j][i] := \{\};
      od;
  od;
  setup.info := [NewHT(regvec,Size(f)^(codims[1]) * 3)];
  setup.suborbnr := [0];
  setup.sumstabl := [0];
  setup.regvecs := [regvec];
  setup.cosetinfo := [];
  setup.cosetrecog := [];
  setup.op := List([1..k+1],i->OnRight);
  setup.sample := [regvec,gens[1][1][1]];

  Objectify( NewType( OrbitBySuborbitSetupFamily,
                      IsOrbitBySuborbitSetup and IsStdOrbitBySuborbitSetupRep ),
             setup );
  # From now on we can use it and it is an object!

  neededfullspace := false;

  # Now do the other steps:
  for j in [2..k] do
      # First find a vector the orbit of which identifies the U_{j-1}-cosets
      # of U_j, i.e. Stab_{U_j}(v) <= U_{j-1}, 
      # we can use the j-1 infrastructure!
      if not(neededfullspace) then
        # if we have needed the full space somewhere, we need it everywhere
        # else, because OrbitBySuborbit is only usable for big vectors!
        Info(InfoOrb,1,"Looking for U",j-1,"-coset-recognising U",j,"-orbit ",
             "in factor space...");
        regvec := ZeroVector(sample,codims[j]);
        counter := 0;
        repeat
            Randomize(regvec);
            counter := counter + 1;
            o := OrbitBySuborbit(regvec,(sizes[j]/sizes[j-1])*2+1,sizes[j],
                                 setup,100);
            Info(InfoOrb,2,"Found ",Length(Representatives(o!.db)),
                 " suborbits (need ",sizes[j]/sizes[j-1],")");
        until Length(Representatives(o!.db)) = sizes[j]/sizes[j-1] or 
              counter >= 3;
      fi;
      if neededfullspace or
         Length(Representatives(o!.db)) < sizes[j]/sizes[j-1] then
        neededfullspace := true;
        # Bad luck, try the full space:
        Info(InfoOrb,1,"Looking for U",j-1,"-coset-recognising U",j,"-orbit ",
             "in full space...");
        regvec := ZeroMutable(sample);
        counter := 0;
        # Go to the original generators, using the infrastructure for k=j-1:
        merk := [setup!.els[j],setup!.elsinv[j]];
        setup!.els[j] := Concatenation(gens{[1..j]});
        setup!.elsinv[j] := List(setup!.els[j],x->x^-1);
        repeat
            Randomize(regvec);
            counter := counter + 1;
            o := OrbitBySuborbit(regvec,(sizes[j]/sizes[j-1])*2+1,sizes[j],
                                 setup,100);
            Info(InfoOrb,2,"Found ",Length(Representatives(o!.db)),
                 " suborbits (need ",sizes[j]/sizes[j-1],")");
        until Length(Representatives(o!.db)) = sizes[j]/sizes[j-1] or
              counter >= 20;
        if Length(Representatives(o!.db)) < sizes[j]/sizes[j-1] then
            Info(InfoOrb,1,"Bad luck, did not find nice orbit, giving up.");
            return;
        fi;
        setup!.els[j] := merk[1];
        setup!.elsinv[j] := merk[2];
      fi;

      Info(InfoOrb,1,"Found U",j-1,"-coset-recognising U",j,"-orbit!");
      setup!.k := j;
      setup!.size[j] := sizes[j];
      setup!.index[j] := sizes[j]/sizes[j-1];
      setup!.trans[j] := o!.words;
      setup!.suborbnr[j] := 0;
      setup!.sumstabl[j] := 0;
      setup!.info[j] :=
            NewHT(regvec,QuoInt(Size(f)^(codims[j]),sizes[j-1])*4+1); # fixme!
      setup!.regvecs[j] := regvec;
      if not(neededfullspace) then
          setup!.cosetrecog[j] := ORB_CosetRecogGenericFactorSpace;
          setup!.cosetinfo[j] := o!.db;   # the hash table
      else
          setup!.cosetrecog[j] := ORB_CosetRecogGenericFullSpace;
          setup!.cosetinfo[j] := [o!.db,k];   # the hash table
      fi;
      setup!.sample[j] := ZeroVector(sample,codims[j]);
      setup!.sample[j+1] := sample;
  od;
  return setup;
end );

InstallGlobalFunction( ORB_CosetRecogGenericFactorSpace,
  function( j, w, s )
    local x;
    x := ORB_ApplyWord(s!.regvecs[j],w,s!.els[j],s!.elsinv[j],s!.op[j]);
    x := ORB_Minimalize(x,j,j-1,s,false,false);
    return LookupSuborbit(x,s!.cosetinfo[j]);
  end );

InstallGlobalFunction( ORB_CosetRecogGenericFullSpace,
  function( j, w, s )
    local x,k;
    k := s!.cosetinfo[j][2];
    x := ORB_ApplyWord(s!.regvecs[j],w,s!.els[k+1],s!.elsinv[k+1],
                       s!.op[k+1]);
    x := ORB_Minimalize(x,k+1,j-1,s,false,false);
    return LookupSuborbit(x,s!.cosetinfo[j][1]);
  end );

InstallGlobalFunction( OrbitBySuborbitBootstrapForLines,
function(gens,permgens,sizes,codims)
  # Returns a setup object for a list of helper subgroups
  # gens: a list of lists of generators for U_1 < U_2 < ... < U_k < G
  # permgens: the same in a faithful permutation representation
  # sizes: a list of sizes of groups U_1 < U_2 < ... < U_k
  # codims: a list of dimensions of factor modules
  # note that the basis must be changed to make projection easy!
  # That is, projection is taking the components [1..codim].

  local dim,doConversions,f,i,j,k,nrgens,nrgenssum,o,regvec,sample,setup,sum,v,
        counter,merk,neededfullspace,c;

  # For the old compressed matrices:
  if IsGF2MatrixRep(gens[1][1]) or Is8BitMatrixRep(gens[1][1]) then
      doConversions := true;
  else
      doConversions := false;
  fi;

  # Some preparations:
  k := Length(sizes);
  if Length(gens) <> k+1 or Length(permgens) <> k+1 or Length(codims) <> k then
      Error("Need generators for ",k+1," groups and ",k," codimensions.");
      return;
  fi;
  nrgens := List(gens,Length);
  nrgenssum := 0*nrgens;
  sum := 0;
  for i in [1..k+1] do
      nrgenssum[i] := sum;
      sum := sum + nrgens[i];
  od;
  nrgenssum[k+2] := sum;

  sample := gens[1][1][1];  # first vector of first generator

  # Do the first step:
  setup := rec(k := 1);
  setup.size := [sizes[1]];
  setup.index := [sizes[1]];
  setup.permgens := Concatenation(permgens);
  setup.permgensinv := List(setup.permgens,x->x^-1);
  setup.els := [];
  setup.els[k+1] := Concatenation(gens);
  setup.elsinv := [];
  setup.elsinv[k+1] := List(setup.els[k+1],x->x^-1);
  dim := Length(gens[1][1]);
  codims[k+1] := dim;   # for the sake of completeness!
  for j in [1..k] do
      setup.els[j] := List(Concatenation(gens{[1..j]}),
                           x->ExtractSubMatrix(x,[1..codims[j]],
                                                 [1..codims[j]]));
      if doConversions then
          for i in setup.els[j] do ConvertToMatrixRep(i); od;
      fi;
      setup.elsinv[j] := List(setup.els[j],x->x^-1);
  od;
  f := BaseField(gens[1][1]);
  regvec := ZeroVector(sample,codims[1]);  
            # a new empty vector over same field
  Info(InfoOrb,1,"Looking for regular U1-orbit in factor space...");
  counter := 0;
  repeat
      counter := counter + 1;
      Randomize(regvec);
      c := PositionNonZero( regvec );
      if c <= Length( regvec )  then
          regvec := Inverse( regvec[c] ) * regvec;
      fi;
      o := Enumerate(InitOrbit(setup.els[1],regvec,OnLines,sizes[1]*2,
                               rec(schreier := true)));
      Info(InfoOrb,2,"Found length: ",Length(o!.orbit));
  until Length(o!.orbit) = sizes[1] or counter >= 10;
  if Length(o!.orbit) < sizes[1] then   # Bad luck, try something else:
    regvec := ZeroMutable(sample);
    Info(InfoOrb,1,"Looking for regular U1-orbit in full space...");
    counter := 0;
    repeat
        counter := counter + 1;
        Randomize(regvec);
        c := PositionNonZero( regvec );
        if c <= Length( regvec )  then
            regvec := Inverse( regvec[c] ) * regvec;
        fi;
        o := Enumerate(InitOrbit(gens[1],regvec,OnLines,sizes[1]*2,
                                 rec(schreier := true)));
        Info(InfoOrb,2,"Found length: ",Length(o!.orbit));
    until Length(o!.orbit) = sizes[1] or counter >= 10;
    if Length(o!.orbit) < sizes[1] then   # Again bad luck, try the regular rep
        Info(InfoOrb,1,"Using the permutation representation...");
        o := Enumerate(InitOrbit(permgens[1],permgens[1]^0,OnRight,sizes[1]*2,
                                 rec(schreier := true)));
    fi;
  fi;
  Info(InfoOrb,2,"Found!");
  setup.trans := [List([1..Length(o!.orbit)],i->TraceSchreierTreeForward(o,i))];

  # Note that for k=1 we set codims[2] := dim
  setup.pi := [];
  setup.pifunc := [];
  for j in [2..k+1] do
      setup.pi[j] := [];
      setup.pifunc[j] := [];
      for i in [1..j-1] do
          setup.pi[j][i] := [1..codims[i]];
          setup.pifunc[j][i] := \{\};
      od;
  od;
  setup.info := [NewHT(regvec,Size(f)^(codims[1]) * 3)];
  setup.suborbnr := [0];
  setup.sumstabl := [0];
  setup.regvecs := [regvec];
  setup.cosetinfo := [];
  setup.cosetrecog := [];
  setup.op := List([1..k+1],i->OnLines);
  setup.sample := [regvec,gens[1][1][1]];

  Objectify( NewType( OrbitBySuborbitSetupFamily,
                      IsOrbitBySuborbitSetup and IsStdOrbitBySuborbitSetupRep ),
             setup );
  # From now on we can use it and it is an object!

  neededfullspace := false;

  # Now do the other steps:
  for j in [2..k] do
      # First find a vector the orbit of which identifies the U_{j-1}-cosets
      # of U_j, i.e. Stab_{U_j}(v) <= U_{j-1}, 
      # we can use the j-1 infrastructure!
      if not(neededfullspace) then
        # if we have needed the full space somewhere, we need it everywhere
        # else, because OrbitBySuborbit is only usable for big vectors!
        Info(InfoOrb,1,"Looking for U",j-1,"-coset-recognising U",j,"-orbit ",
             "in factor space...");
        regvec := ZeroVector(sample,codims[j]);
        counter := 0;
        repeat
            Randomize(regvec);
            c := PositionNonZero( regvec );
            if c <= Length( regvec )  then
                regvec := Inverse( regvec[c] ) * regvec;
            fi;
            counter := counter + 1;
            o := OrbitBySuborbit(regvec,(sizes[j]/sizes[j-1])*2+1,sizes[j],
                                 setup,100);
            Info(InfoOrb,2,"Found ",Length(Representatives(o!.db)),
                 " suborbits (need ",sizes[j]/sizes[j-1],")");
        until Length(Representatives(o!.db)) = sizes[j]/sizes[j-1] or 
              counter >= 3;
      fi;
      if neededfullspace or
         Length(Representatives(o!.db)) < sizes[j]/sizes[j-1] then
        neededfullspace := true;
        # Bad luck, try the full space:
        Info(InfoOrb,1,"Looking for U",j-1,"-coset-recognising U",j,"-orbit ",
             "in full space...");
        regvec := ZeroMutable(sample);
        counter := 0;
        # Go to the original generators, using the infrastructure for k=j-1:
        merk := [setup!.els[j],setup!.elsinv[j]];
        setup!.els[j] := Concatenation(gens{[1..j]});
        setup!.elsinv[j] := List(setup!.els[j],x->x^-1);
        repeat
            Randomize(regvec);
            c := PositionNonZero( regvec );
            if c <= Length( regvec )  then
                regvec := Inverse( regvec[c] ) * regvec;
            fi;
            counter := counter + 1;
            o := OrbitBySuborbit(regvec,(sizes[j]/sizes[j-1])*2+1,sizes[j],
                                 setup,100);
            Info(InfoOrb,2,"Found ",Length(Representatives(o!.db)),
                 " suborbits (need ",sizes[j]/sizes[j-1],")");
        until Length(Representatives(o!.db)) = sizes[j]/sizes[j-1] or
              counter >= 20;
        if Length(Representatives(o!.db)) < sizes[j]/sizes[j-1] then
            Info(InfoOrb,1,"Bad luck, did not find nice orbit, giving up.");
            return;
        fi;
        setup!.els[j] := merk[1];
        setup!.elsinv[j] := merk[2];
      fi;

      Info(InfoOrb,2,"Found U",j-1,"-coset-recognising U",j,"-orbit!");
      setup!.k := j;
      setup!.size[j] := sizes[j];
      setup!.index[j] := sizes[j]/sizes[j-1];
      setup!.trans[j] := o!.words;
      setup!.suborbnr[j] := 0;
      setup!.sumstabl[j] := 0;
      setup!.info[j] :=
            NewHT(regvec,QuoInt(Size(f)^(codims[j]),sizes[j-1])*4+1); # fixme!
      setup!.regvecs[j] := regvec;
      if not(neededfullspace) then
          setup!.cosetrecog[j] := ORB_CosetRecogGenericFactorSpace;
          setup!.cosetinfo[j] := o!.db;   # the hash table
      else
          setup!.cosetrecog[j] := ORB_CosetRecogGenericFullSpace;
          setup!.cosetinfo[j] := [o!.db,k];   # the hash table
      fi;
      setup!.sample[j] := ZeroVector(sample,codims[j]);
      setup!.sample[j+1] := sample;
  od;
  return setup;
end );

