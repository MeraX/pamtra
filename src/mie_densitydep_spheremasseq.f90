subroutine mie_densitydep_spheremasseq(f, t, m_ice,    &
     a_mtox, bcoeff, dia1, dia2, nbins, maxleg, ad, bd, alpha, &
     gamma, lphase_flag, extinction, albedo, back_scatt, nlegen, legen,  &
     legen2, legen3, legen4, aerodist,density,wc)
  !    computing the scattering properties according to                  
  !    ice sphere model, i.e. the electromagnetic properties of the      
  !     particle are computed by assuming that they are the same          
  !     as the equivalent mass sphere
  !                                     
  ! note that mindex has the convention with negative imaginary part      

  use kinds
  use constants, only: pi,c

  implicit none

  real(kind=dbl), intent(in) :: f,  &! frequency [GHz]
       t    ! temperature [K]

  integer :: maxleg, nlegen, nbins
  logical :: lphase_flag 
  real(kind=dbl) :: wavelength, dia1, dia2
  real(kind=dbl), intent(in) :: ad, bd, alpha, gamma
  complex(kind=dbl) :: m_ice
  real(kind=dbl) :: a_mtox, bcoeff,tot_mass,wc
  real(kind=dbl) :: extinction, albedo, back_scatt, legen (200), legen2 (200),&
       legen3 (200), legen4 (200)                                        
  integer, parameter :: maxn  = 5000
  integer :: nterms, nquad, nmie, nleg 
  integer :: i, l, m, ir
  real(kind=dbl) :: x, del_d, diameter, ndens, tmp, diameter_ice, density
  real(kind=dbl) :: qext, qscat, qback, scatter 
  real(kind=dbl) :: distribution 
  real(kind=dbl) :: mu(maxn), wts(maxn)
  real(kind=dbl) :: p1, pl, pl1, pl2, p2, p3, p4 
  real(kind=dbl) :: sumqe, sumqs, sumqback
  real(kind=dbl), dimension(maxn) :: sump1, coef1, sump2, coef2,   &
       sump3, coef3, sump4, coef4            
  complex(kind=dbl), dimension(maxn) :: a, b
  complex(kind=dbl) :: msphere, eps_mix
  character :: aerodist * 1

  wavelength = c/(f*1.e9) !

  !           find the maximum number of terms required in the mie series,
  !       call density_ice(a_mtox, bcoeff, rad2, dens_graup) 
  !       rad2_ice = (dens_graup / 917.) **0.33333333 * rad2 
  diameter_ice = (6.*a_mtox*dia2**bcoeff/(pi*density))**(1./3.)

  msphere = eps_mix((1.d0,0.d0),m_ice,density)

  x = pi * diameter_ice / wavelength
  nterms = 0 
  call miecalc (nterms, x, msphere, a, b) 
  nlegen = 2 * nterms 
  nlegen = min(maxleg, nlegen) 
  nquad = (nlegen + 2 * nterms + 2) / 2 
  if (nquad.gt.maxn) stop 'mie: maxn exceeded' 

  !           get the gauss-legendre quadrature abscissas and weights     
  call gausquad(nquad, mu, wts) 

  sumqe = 0.0d0 
  sumqs = 0.0d0 
  sumqback = 0.0d0 
  do i = 1, nquad 
     sump1 (i) = 0.0d0 
     sump2 (i) = 0.0d0 
     sump3 (i) = 0.0d0 
     sump4 (i) = 0.0d0 
  end do

  !               integration loop over diameter of spheres
  if (nbins .gt. 0) del_d = (dia2 - dia1) / nbins
  tot_mass = 0.
   do ir = 1, nbins+1
     diameter = dia1 + (ir - 1) * del_d
     ndens = distribution(ad, bd, alpha, gamma, diameter, aerodist)
     if ( (ir .eq. 1 .or. ir .eq. nbins+1) .and. nbins .gt. 0) then
        ndens = 0.5 * ndens 
     end if
     tot_mass = tot_mass + ndens*del_d*a_mtox*diameter**bcoeff
     if ((ir .eq. nbins+1) .and. (tot_mass/wc*100. .lt. 99.9d0)) then
      ndens = ndens + (wc-tot_mass)/(del_d*a_mtox*(diameter)**bcoeff)
      tot_mass = wc
     end if

     nmie = 0 

     !       call density_ice(a_mtox, bcoeff, radius, dens_graup) 
     ! !         write(18,*)'dens',dens_graup                                  
     !       radius_ice = (dens_graup / 917.) **0.33333333 * radius 

     diameter_ice = (6.*a_mtox*diameter**bcoeff/(pi*density))**(1./3.)
     x = pi * diameter_ice / wavelength

	 msphere = eps_mix((1.d0,0.d0),m_ice,density)

     call miecalc (nmie, x, msphere, a, b) 
     call miecross (nmie, x, a, b, qext, qscat, qback)
     ! sum up extinction, scattering, and backscattering as cross-sections/pi
     sumqe = sumqe+qext * ndens * (diameter_ice/2.)**2         ! [1/m^2]
     sumqs = sumqs + qscat * ndens * (diameter_ice/2.)**2      ! [1/m^2]
     sumqback = sumqback + qback * ndens * (diameter_ice/2.)**2! [1/m^2]
     if (lphase_flag) then 
        nmie = min0(nmie, nterms) 
        do i = 1, nquad 
           call mieangle (nmie, a, b, mu (i), p1, p2, p3, p4) 
           sump1 (i) = sump1 (i) + p1 * ndens 
           sump2 (i) = sump2 (i) + p2 * ndens 
           sump3 (i) = sump3 (i) + p3 * ndens 
           sump4 (i) = sump4 (i) + p4 * ndens 
        end do
     end if
     tot_mass = tot_mass + ndens*del_d*a_mtox*diameter**bcoeff
  end do

  !           multiply the sums by the integration delta and other constan
  !             put quadrature weights in angular array for later         
  if (nbins.eq.0) del_d = 1.0d0

  extinction = pi * sumqe * del_d
  scatter = pi * sumqs * del_d
  back_scatt = pi * sumqback * del_d
  albedo = scatter / extinction 

  !         if the phase function is not desired then leave now           
  if ( .not. lphase_flag) return 

  tmp = (wavelength**2 / (pi * scatter) ) * del_d
  do i = 1, nquad 
     sump1 (i) = tmp * sump1 (i) * wts (i) 
     sump2 (i) = tmp * sump2 (i) * wts (i) 
     sump3 (i) = tmp * sump3 (i) * wts (i) 
     sump4 (i) = tmp * sump4 (i) * wts (i) 
  end do

  !           integrate the angular scattering functions times legendre   
  !             polynomials to find the legendre coefficients             
  do m = 1, nlegen + 1 
     coef1 (m) = 0.0d0 
     coef2 (m) = 0.0d0 
     coef3 (m) = 0.0d0 
     coef4 (m) = 0.0d0 
  end do
  !           use upward recurrence to find legendre polynomials          
  do i = 1, nquad 
     pl1 = 1.0d0 
     pl = 1.0d0 
     do l = 0, nlegen 
        m = l + 1 
        if (l .gt. 0) pl = (2*l-1)*mu(i)*pl1/l-(l-1)*pl2/l                                                                 
        coef1 (m) = coef1 (m) + sump1 (i) * pl 
        coef2 (m) = coef2 (m) + sump2 (i) * pl 
        coef3 (m) = coef3 (m) + sump3 (i) * pl 
        coef4 (m) = coef4 (m) + sump4 (i) * pl 
        pl2 = pl1 
        pl1 = pl 
     end do
  end do
  nleg = nlegen 
  do l = 0, nleg 
     m = l + 1 
     legen (m) = (2 * l + 1) / 2.0 * coef1 (m) 
     legen2 (m) = (2 * l + 1) / 2.0 * coef2 (m) 
     legen3 (m) = (2 * l + 1) / 2.0 * coef3 (m) 
     legen4 (m) = (2 * l + 1) / 2.0 * coef4 (m) 
     if (legen (m) .gt. 1.0e-7) nlegen = l 
  end do

  return 

end subroutine mie_densitydep_spheremasseq