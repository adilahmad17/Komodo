include "kev_constants.dfy"
include "Maybe.dfy"
include "pagedb.dfy"

//=============================================================================
// Utilities
//=============================================================================
datatype smcReturn = Pair(pageDbOut: PageDb, err: int)

function pagedbFrmRet(ret:smcReturn): PageDb
    { match ret case Pair(p,e) => p }

function errFrmRet(ret:smcReturn): int 
    { match ret case Pair(p,e) => e }

function pageIsFree(d:PageDb, pg:PageNr) : bool
    requires pg in d;
    { d[pg].PageDbEntryFree? }

// a points to an address space and it is closed
predicate validAddrspacePage(d: PageDb, a: PageNr)
    requires wellFormedPageDb(d)
{
    isAddrspace(d, a) && d[a].entry.l1ptnr in d
}

//a============================================================================
// Behavioral Specification of Monitor Calls
//=============================================================================
function initAddrspace_inner(pageDbIn: PageDb, addrspacePage: PageNr, l1PTPage: PageNr)
    : smcReturn
    requires validPageDb(pageDbIn);
{
    var g := pageDbIn;
    if(!validPageNr(addrspacePage) || !validPageNr(l1PTPage) ||
        addrspacePage == l1PTPage) then
        Pair(pageDbIn, KEV_ERR_INVALID_PAGENO())
    else if(l1PTPage % 4 != 0) then
        Pair(pageDbIn, KEV_ERR_INVALID_PAGENO())
    else if( !g[addrspacePage].PageDbEntryFree? || !g[l1PTPage].PageDbEntryFree? ) then
        Pair(pageDbIn, KEV_ERR_PAGEINUSE())
    else
        var addrspace := Addrspace(l1PTPage, 1, InitState);
        var l1PT := L1PTable(SeqRepeat(NR_L1PTES(),Nothing));
        var pageDbOut := 
            (pageDbIn[addrspacePage := PageDbEntryTyped(addrspacePage, addrspace)])[
                l1PTPage := PageDbEntryTyped(addrspacePage, l1PT)];
        Pair(pageDbOut, KEV_ERR_SUCCESS())
}

function initDispatcher_inner(pageDbIn: PageDb, page:PageNr, addrspacePage:PageNr,
    entrypoint:int)
    : smcReturn
    requires validPageDb(pageDbIn);
{
   var n := page;
   var d := pageDbIn;
   if(!isAddrspace(pageDbIn, addrspacePage)) then
       Pair(pageDbIn, KEV_ERR_INVALID_ADDRSPACE())
   else
       allocatePage(pageDbIn, page, addrspacePage, Dispatcher(entrypoint, false))
}

function allocatePage_inner(pageDbIn: PageDb, securePage: PageNr,
    addrspacePage:PageNr, entry:PageDbEntryTyped) : smcReturn
    requires validPageDb(pageDbIn)
    requires validAddrspacePage(pageDbIn, addrspacePage)
    requires closedRefsPageDbEntry(entry)
    requires !entry.L1PTable?
    requires !entry.Addrspace?
    requires entry.L2PTable? ==> entry.l2pt == []
{
    var addrspace := pageDbIn[addrspacePage].entry;
    if(!validPageNr(securePage)) then Pair(pageDbIn, KEV_ERR_INVALID_PAGENO())
    else if(!pageIsFree(pageDbIn, securePage)) then Pair(pageDbIn, KEV_ERR_PAGEINUSE())
    else if(addrspace.state != InitState) then
        Pair(pageDbIn,KEV_ERR_ALREADY_FINAL())
    // TODO ?? Model page clearing for non-data pages?
    else
        var updatedAddrspace := match addrspace
            case Addrspace(l1, ref, state) => Addrspace(l1, ref + 1, state);
        var pageDbOut := (pageDbIn[
            securePage := PageDbEntryTyped(addrspacePage, entry)])[
            addrspacePage := PageDbEntryTyped(addrspacePage, updatedAddrspace)];
        Pair(pageDbOut, KEV_ERR_SUCCESS())
}

function remove_inner(pageDbIn: PageDb, page: PageNr) : smcReturn
    requires validPageDb(pageDbIn)
{
    if(!validPageNr(page)) then
        Pair(pageDbIn, KEV_ERR_INVALID_PAGENO())
    else if(pageDbIn[page].PageDbEntryFree?) then
        Pair(pageDbIn, KEV_ERR_SUCCESS())
    else 
        var e := pageDbIn[page].entry;
        var addrspacePage := pageDbIn[page].addrspace;
        var addrspace := pageDbIn[addrspacePage].entry;
        if( e.Addrspace? ) then
           if(e.refcount !=0) then Pair(pageDbIn, KEV_ERR_PAGEINUSE())
           else Pair(pageDbIn[page := PageDbEntryFree], KEV_ERR_SUCCESS())
        else 
            if( !addrspace.state.StoppedState?) then
                Pair(pageDbIn, KEV_ERR_NOT_STOPPED())
            else 
                assert page in addrspaceRefs(pageDbIn, addrspacePage);
                var updatedAddrspace := match addrspace
                    case Addrspace(l1, ref, state) => Addrspace(l1, ref - 1, state);
                var pageDbOut := (pageDbIn[page := PageDbEntryFree])[
                    addrspacePage := PageDbEntryTyped(addrspacePage, updatedAddrspace)];
                Pair(pageDbOut, KEV_ERR_SUCCESS())
}

//=============================================================================
// Hoare Specification of Monitor Calls
//=============================================================================
// (i.e. specs with postconditions)

function initAddrspace(pageDbIn: PageDb, addrspacePage: PageNr, l1PTPage: PageNr)
    : smcReturn
    requires validPageDb(pageDbIn);
    ensures  validPageDb(pagedbFrmRet(initAddrspace(pageDbIn, addrspacePage, l1PTPage)));
{
    initAddrspacePreservesPageDBValidity(pageDbIn, addrspacePage, l1PTPage);
    initAddrspace_inner(pageDbIn, addrspacePage, l1PTPage)
}

function initDispatcher(pageDbIn: PageDb, page:PageNr, addrspacePage:PageNr,
    entrypoint:int)
    : smcReturn
    requires validPageDb(pageDbIn);
    ensures  validPageDb(pagedbFrmRet(initDispatcher(pageDbIn, page, addrspacePage, entrypoint)));
{
    initDispatcher_inner(pageDbIn, page, addrspacePage, entrypoint)
}

function allocatePage(pageDbIn: PageDb, securePage: PageNr,
    addrspacePage:PageNr, entry:PageDbEntryTyped ) : smcReturn
    requires validPageDb(pageDbIn)
    requires validAddrspacePage(pageDbIn, addrspacePage)
    requires closedRefsPageDbEntry(entry)
    requires !entry.L1PTable?
    requires !entry.Addrspace?
    requires entry.L2PTable? ==> entry.l2pt == []
    ensures  validPageDb(pagedbFrmRet(allocatePage(pageDbIn, securePage, addrspacePage, entry)));
{
    allocatePagePreservesPageDBValidity(pageDbIn, securePage, addrspacePage, entry);
    allocatePage_inner(pageDbIn, securePage, addrspacePage, entry)
}

function remove(pageDbIn: PageDb, page: PageNr) : smcReturn
    requires validPageDb(pageDbIn)
    ensures  validPageDb(pagedbFrmRet(remove(pageDbIn, page)))
{
    removePreservesPageDBValidity(pageDbIn, page);
    remove_inner(pageDbIn, page)
}

//=============================================================================
// Properties of Monitor Calls
//=============================================================================

//-----------------------------------------------------------------------------
// PageDb Validity Preservation
//-----------------------------------------------------------------------------
lemma initAddrspacePreservesPageDBValidity(pageDbIn : PageDb,
    addrspacePage : PageNr, l1PTPage : PageNr)
    requires validPageDb(pageDbIn)
    ensures validPageDb(pagedbFrmRet(initAddrspace_inner(pageDbIn, addrspacePage, l1PTPage)))
{
     var pageDbOut := pagedbFrmRet(initAddrspace_inner(pageDbIn, addrspacePage, l1PTPage));
     var errOut := errFrmRet(initAddrspace_inner(pageDbIn, addrspacePage, l1PTPage));

     if( errOut != KEV_ERR_SUCCESS() ) {
        // The error case is trivial because PageDbOut == PageDbIn
     } else {
         // Necessary semi-manual proof of validPageDbEntry(pageDbOut, l1PTPage)
         // The interesting part of the proof deals with the contents of addrspaceRefs
         assert forall p :: p != l1PTPage ==> !(p in addrspaceRefs(pageDbOut, addrspacePage));
	     assert l1PTPage in addrspaceRefs(pageDbOut, addrspacePage);
         assert addrspaceRefs(pageDbOut, addrspacePage) == {l1PTPage};
         // only kept for readability
         assert validPageDbEntry(pageDbOut, l1PTPage);

         // Manual proof that the umodified pageDb entries are still valid. The only
         // interesting case is for addrspaces other than the newly created one.
         // Specifically, the only non-trivial aspect of validity is the reference
         // count. Their references are not corrupted because the only touched
         // pages only reference the newly created page.
         ghost var otherAddrspaces := set n : PageNr
            | validPageNr(n) && 0 <= n < KEVLAR_SECURE_NPAGES()
              && pageDbOut[n].PageDbEntryTyped?
              && pageDbOut[n].entry.Addrspace?
              && n != addrspacePage && n != l1PTPage;
         assert forall n :: n in otherAddrspaces ==>
             addrspaceRefs(pageDbOut, n) == addrspaceRefs(pageDbIn, n);
         // only kept for readability
         assert forall n :: n in otherAddrspaces  ==>
             validPageDbEntryTyped(pageDbOut, n);

         assert pageDbEntriesValid(pageDbOut);
         assert validPageDb(pageDbOut);
    }
}


lemma allocatePagePreservesPageDBValidity(pageDbIn: PageDb,
    securePage: PageNr, addrspacePage: PageNr, entry: PageDbEntryTyped)
    requires validPageDb(pageDbIn)
    requires validAddrspacePage(pageDbIn, addrspacePage)
    requires closedRefsPageDbEntry(entry)
    requires !entry.Addrspace?
    requires !entry.L1PTable?
    requires entry.L2PTable? ==> entry.l2pt == []
    ensures  validPageDb(pagedbFrmRet(allocatePage_inner(
        pageDbIn, securePage, addrspacePage, entry)));
{
    var pageDbOut := pagedbFrmRet(allocatePage_inner(
        pageDbIn, securePage, addrspacePage, entry));
    var errOut := errFrmRet(allocatePage_inner(
        pageDbIn, securePage, addrspacePage, entry));

    if ( errOut != KEV_ERR_SUCCESS() ){
        // The error case is trivial because PageDbOut == PageDbIn
    } else {
      
        forall () ensures validPageDbEntry(pageDbOut, addrspacePage);
        {
            var oldRefs := addrspaceRefs(pageDbIn, addrspacePage);
            assert addrspaceRefs(pageDbOut, addrspacePage ) == oldRefs + {securePage};
            
            var addrspace := pageDbOut[addrspacePage].entry;
            assert addrspace.refcount == |addrspaceRefs(pageDbOut, addrspacePage)|;
            assert validAddrspacePage(pageDbOut, addrspacePage);
        }

        forall ( n | validPageNr(n) && n != addrspacePage && n != securePage )
            ensures validPageDbEntry(pageDbOut, n)
        {
            assert addrspaceRefs(pageDbOut, n) == addrspaceRefs(pageDbIn, n);
        }

        assert pageDbEntriesValid(pageDbOut);
        assert validPageDb(pageDbOut);
    }
}


lemma removePreservesPageDBValidity(pageDbIn: PageDb, page: PageNr)
    requires validPageDb(pageDbIn)
    ensures  validPageDb(pagedbFrmRet(remove_inner(pageDbIn, page)))
{

    var pageDbOut := pagedbFrmRet(remove_inner(pageDbIn, page));
    var errOut := errFrmRet(remove_inner(pageDbIn, page));

    if ( errOut != KEV_ERR_SUCCESS() ){
       // trivial
    } else if( pageDbIn[page].PageDbEntryFree?) {
        // trivial
    } else {

        var entry := pageDbIn[page].entry;
        var addrspacePage := pageDbIn[page].addrspace;

        forall () ensures validPageDbEntry(pageDbOut, addrspacePage);
        {
            if(entry.Addrspace?){
            } else {
                var addrspace := pageDbOut[addrspacePage].entry;

                var oldRefs := addrspaceRefs(pageDbIn, addrspacePage);
                assert addrspaceRefs(pageDbOut, addrspacePage) == oldRefs - {page};
                assert addrspace.refcount == |addrspaceRefs(pageDbOut, addrspacePage)|;
                
                //assert validAddrspace(pageDbOut, addrspace);
                assert validAddrspacePage(pageDbOut, addrspacePage);
            }
        }

        assert validPageDbEntry(pageDbOut, page);

        forall ( n | validPageNr(n) && n != addrspacePage && n != page )
            ensures validPageDbEntry(pageDbOut, n)
        {
            if(pageDbOut[n].PageDbEntryFree?) {
                // trivial
            } else {
                var e := pageDbOut[n].entry;
                var d := pageDbOut;
                var a := pageDbOut[n].addrspace;

                assert pageDbOut[n] == pageDbIn[n];

                
                forall () ensures pageDbEntryOk(d, n){
                  
                    // This is a proof that the addrspace of n is still an addrspace
                    //
                    // The only interesting case is when the page that was
                    // removed is the addrspace of n (i.e. a == page). This
                    // case causes an error because a must have been valid in
                    // pageDbIn and therefore n has a reference to it.
                    forall() ensures a in d && d[a].PageDbEntryTyped?
                        && d[a].entry.Addrspace?;
                    {
                        assert a == page ==> n in addrspaceRefs(pageDbIn, a);
                        assert a == page ==> pageDbIn[a].entry.refcount > 0;
                        assert a != page;
                    }

                    if( a == addrspacePage ) {
                        var oldRefs := addrspaceRefs(pageDbIn, addrspacePage);
                        assert addrspaceRefs(pageDbOut, addrspacePage) == oldRefs - {page};
                        assert pageDbOut[a].entry.refcount == |addrspaceRefs(pageDbOut, addrspacePage)|;
                    } else {
                        assert pageDbOut[a].entry.refcount == pageDbIn[a].entry.refcount;
                        assert addrspaceRefs(pageDbIn, a) == addrspaceRefs(pageDbOut, a);
                    }

                }

            }
        }

        assert pageDbEntriesValid(pageDbOut);
        assert validPageDb(pageDbOut);
    }
}

