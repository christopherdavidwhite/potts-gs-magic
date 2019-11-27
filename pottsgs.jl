#julia pottsgs.jl --length 10 --dtheta 0.25 --outdir /home/christopher/work/2019-10-MAGIC/data --subdate TEST

using ITensors
using ArgParse
using ProgressMeter
using Serialization
import ITensors.op
import ITensors.randomMPS

git_commit() = String(read(pipeline(`git log`, `head -1`, `cut -d ' ' -f 2`, `cut -b 1-7`))[1:end-1])
git_commit(path :: String) = cd(git_commit, path)

function pottsSites(N :: Int; q :: Int = 3)
  return [Index(q, "Site,Potts,n=$n") for n = 1:N]
end

randomMPS(sites, χ :: Int64) = randomMPS(Float64, sites, χ)
function randomMPS(::Type{S}, sites, χ :: Int64) where S <: Number
    N = length(sites)
    links = [Index(χ, "Link,l=$ii") for ii in 1:N-1]

    M = MPS(sites)
    M[1] = randomITensor(S, links[1], sites[1])
    for j = 2:N-1
        M[j] = randomITensor(S, links[j-1], links[j], sites[j])
    end
    M[N] = randomITensor(S, links[N-1], sites[N])
    return M
end

const PottsSite = makeTagType("Potts")

# 1-index my Potts states
# so diagonal elements of Z are
#    e^{2πi/q}
#    e^{2πi*2/q}
#    e^{2πi*3/q}
#    e^{2πi*(q-1)/q}
#    e^{2πi*q/q} = 1
# this seems like the least bad thing
function state(::PottsSite,
               st::AbstractString)
  return parse(Int64, st)
end

function op(::PottsSite,
            s :: Index,
            opname :: AbstractString)::ITensor
  sP = prime(s)
  q = dim(s)

  Op = ITensor(Complex{Float64},dag(s), s')

  if opname == "Z"
    for j in 1:q
      Op[j,j] = exp(2*π*im*j/q)
    end
  elseif opname == "ZH"
    for j in 1:q
      Op[j,j] = exp(-2*π*im*j/q)
    end
  elseif opname == "X"
    for j in 1:q
      Op[(j % q) + 1,j] = 1
    end
  elseif opname == "XH"
    for j in 1:q
      Op[j,(j % q) + 1] = 1
    end
  elseif opname == "X+XH"
    for j in 1:q
      Op[j,(j % q) + 1] = 1
      Op[(j % q) + 1,j] = 1
    end
  else
    throw(ArgumentError("Operator name '$opname' not recognized for PottsSite"))
  end
  return Op
end    

function potts3gs(θ, λ, χ0, sites; quiet=false)
    N = length(sites)
    
    if !quiet @show θ end

    ampo = AutoMPO()
    for j = 1:N-1
        add!(ampo, -sin(θ), "Z", j,"ZH",j+1)
        add!(ampo, -sin(θ), "ZH",j,"Z", j+1)
    end
   
    for j = 1:N
        add!(ampo, -cos(θ), "X",  j)
        add!(ampo, -cos(θ), "XH", j)
        add!(ampo, -λ, "Z",  j)
        add!(ampo, -λ, "ZH", j)
    end

    H = toMPO(ampo, sites);
    
    observer = DMRGObserver(Array{String}(undef,0), sites, 1e-7)
    #observer = DMRGObserver(Array{String}(undef,0), sites)
    
    sweeps = Sweeps(200)
    maxdim!(sweeps, 10,20,100,100,200)
    cutoff!(sweeps, 1E-10)
    noise!(sweeps, 1e-1,1e-2,1e-2,[10.0^(-j) for j in 2:10]...)
    
    ψ0 = randomMPS(Complex{Float64}, sites, χ0)
    E1, ψ1 = dmrg(H,ψ0,sweeps, quiet=quiet, observer=observer) 
    
    ψ0= randomMPS(Complex{Float64}, sites, χ0)
    E2, ψ2 = dmrg(H,ψ0,sweeps, quiet=quiet, observer=observer)

    if abs(E1 - E2) > 1e-6
        @warn("Energy difference: θ = $θ, $E1 vs $E2")
    end
    
    #may have gs degeneracy
    #=
    if abs(1 - abs(ovlp)) > 1e-8
        error("Overlap bad: $θ, $ovlp")
    end
    =#
    return E1, E2, observer.energies, ψ1
end

s = ArgParseSettings()
@add_arg_table s begin
    "--length",    "-l" # help = "chain of length"
    "--dtheta",   default => "0.01"
    "--thetamin", default => "0.1"
    "--thetamax", default => "1.9"
    "--lambda",   default => "0.0"
    "--chi0",     default => "1"
    "--jobname",  default => "M"
    "--outdir"
    "--subdate"
end
opts = parse_args(s)

dθ = parse(Float64, opts["dtheta"])
λ  = parse(Float64, opts["lambda"])
L  = parse(Int64, opts["length"])
χ0 = parse(Int64, opts["chi0"])
jobname = opts["jobname"]

θmin = parse(Float64, opts["thetamin"])
θmax = parse(Float64, opts["thetamax"])

outdir  = opts["outdir"]
subdate = opts["subdate"]

itensors_dir = ENV["ITENSORSJL_DIR"]

dir = "$outdir/$jobname/$subdate/$(git_commit(itensors_dir))-$(git_commit(@__DIR__()))_L$L-thetamin$θmin-dtheta$dθ-thetamax$θmax-lambda$λ-chi0$χ0"
mkpath(dir)

θs = (θmin:dθ:θmax) * π/4
@show L, θs, λ
sites = pottsSites(L)
serialize("$(dir)/sites.p", sites)
@showprogress for (jθ, θ) in enumerate(θs)
    E1,E2,energies, ψ = potts3gs(θ, λ, χ0, sites, quiet=true)
    serialize("$(dir)/$(jθ).p", (θ,E1,E2,energies,ψ))
end
