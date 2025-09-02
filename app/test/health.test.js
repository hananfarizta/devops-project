const request = require("supertest");
const express = require("express");

// Kita akan menguji app secara terisolasi
const app = express();
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

describe("GET /health", () => {
  it("should respond with a 200 status code and a JSON object", async () => {
    const response = await request(app).get("/health");
    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toMatch(/json/);
    expect(response.body).toEqual({ status: "ok" });
  });
});
