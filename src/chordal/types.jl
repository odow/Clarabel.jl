# DataStructures provides OrderedSet, but only because it itself includes
# OrderedCollections.  Could just use OrderedCollections directly,
# but the kruskal! function also uses a function from DataStructures.
# If that is removed then use the lighter weight option here

using DataStructures

abstract type AbstractMergeStrategy end
VertexSet = OrderedSet{DefaultInt}

# OrderedCollections@2 removed getindex(::OrderedSet, ::Int). As a work-around,
# use this method, as suggested here:
# https://github.com/JuliaCollections/DataStructures.jl/pull/180#issuecomment-484877416
function _getindex(set::VertexSet, index::DefaultInt)
    for (i, si) in enumerate(set)
        if i == index
            return si
        end
    end
    return throw(BoundsError(set, index))
end

#PJG: make a settable option
@enum EdgeWeightMethod begin
  CUBIC = 1
end

