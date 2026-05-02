package main

import (
	"log"
	"os"

	"github.com/gofiber/fiber/v3"
)

func main() {
	app := fiber.New()

	app.Get("/", func(c fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"ENV_MESSAGE": os.Getenv("ENV_MESSAGE"),
		})
	})

	log.Fatal(app.Listen(":3000"))
}
