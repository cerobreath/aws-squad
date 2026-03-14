# Build Stage
FROM maven:3.9-amazoncorretto-21 AS build-env

WORKDIR /build

COPY pom.xml .
COPY .mvn .mvn
COPY mvnw .

RUN mvn dependency:go-offline -B -q

COPY ./src ./src

RUN mvn -DskipTests package -q && \
    mv /build/target/ui-0.0.1-SNAPSHOT.jar /app.jar

# Package Stage
FROM amazoncorretto:21-alpine

RUN addgroup -g 1000 appuser && adduser -u 1000 -G appuser -h /app -D appuser

ENV JAVA_TOOL_OPTIONS=
ENV SPRING_PROFILES_ACTIVE=prod

WORKDIR /app
USER appuser

COPY ./ATTRIBUTION.md ./LICENSES.md
COPY --chown=appuser:appuser --from=build-env /app.jar .

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
