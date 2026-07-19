import AmbientBackground from "@/components/AmbientBackground";
import SiteNav from "@/components/SiteNav";
import Hero from "@/components/Hero";
import HowItWorks from "@/components/HowItWorks";
import Features from "@/components/Features";
import Platforms from "@/components/Platforms";
import Providers from "@/components/Providers";
import Advantages from "@/components/Advantages";
import FooterCTA from "@/components/FooterCTA";

export default function Home() {
  return (
    <>
      <AmbientBackground />
      <SiteNav />
      <main className="relative z-10">
        <Hero />
        <HowItWorks />
        <Features />
        <Platforms />
        <Providers />
        <Advantages />
        <FooterCTA />
      </main>
    </>
  );
}
