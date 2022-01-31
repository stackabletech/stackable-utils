package tech.stackable.nifi;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.stream.Collectors;

public class PasswordHasher
{
    public static void main( String[] args )
    {
        String input = getInput();
        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();
        String hash = encoder.encode(input.toCharArray());
        System.out.println(hash);
    }

    private static String getInput() {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        try {
            if (reader.ready()) {
                return reader.lines().collect(Collectors.joining("\n"));
            }
        } catch (IOException e) {
            System.err.println("Failed to read from stdin: " + e.getMessage());
            System.exit(-1);
        }
        // Didn't read anything or an error occurred
        System.exit(-1);
        return "";
    }
}
