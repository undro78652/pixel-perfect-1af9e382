import { createFileRoute, Navigate } from "@tanstack/react-router";

export const Route = createFileRoute("/invite/$token")({
  head: () => ({
    meta: [
      { title: "Invitation — XYZ Society" },
      { name: "description", content: "Accept a family invitation to XYZ Society." },
      { property: "og:title", content: "Invitation — XYZ Society" },
      { property: "og:description", content: "You were invited to join a house in XYZ Society." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => {
    const { token } = Route.useParams();
    return <Navigate to="/register" search={{ invite: token }} />;
  },
});
